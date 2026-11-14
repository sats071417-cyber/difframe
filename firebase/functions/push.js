'use strict';
// アプリの通知（notifications/{owner}/items/{item}）が作られたら、その人の端末に APNs でプッシュを送る。
const crypto = require('crypto');
const http2 = require('http2');

const BUNDLE_ID = 'com.diffframe.app';

// 通知の文面（アプリの画面の文と同じ）
const TEXT = {
  ja: {
    friendRequest: n => `${n} さんから友達リクエストが届きました`,
    friendAccepted: n => `${n} さんと友達になりました`,
    comment: n => `${n} さんがコメントしました`,
    friendPost: n => `${n} さんが投稿しました`,
    like: n => `${n} さんがリアクションしました`,
    message: n => `${n} さんからメッセージ`,
  },
  en: {
    friendRequest: n => `${n} sent you a friend request`,
    friendAccepted: n => `You and ${n} are now friends`,
    comment: n => `${n} commented`,
    friendPost: n => `${n} posted`,
    like: n => `${n} reacted to your post`,
    message: n => `Message from ${n}`,
  },
  zh: {
    friendRequest: n => `${n} 向你发送了好友请求`,
    friendAccepted: n => `你和 ${n} 成为了好友`,
    comment: n => `${n} 发表了评论`,
    friendPost: n => `${n} 发布了新照片`,
    like: n => `${n} 对你的投稿做出了回应`,
    message: n => `来自 ${n} 的消息`,
  },
  ko: {
    friendRequest: n => `${n}님이 친구 요청을 보냈어요`,
    friendAccepted: n => `${n}님과 친구가 되었어요`,
    comment: n => `${n}님이 댓글을 남겼어요`,
    friendPost: n => `${n}님이 게시했어요`,
    like: n => `${n}님이 반응을 남겼어요`,
    message: n => `${n}님의 메시지`,
  },
  es: {
    friendRequest: n => `${n} te envió una solicitud de amistad`,
    friendAccepted: n => `Ahora eres amigo de ${n}`,
    comment: n => `${n} comentó`,
    friendPost: n => `${n} publicó`,
    like: n => `${n} reaccionó a tu publicación`,
    message: n => `Mensaje de ${n}`,
  },
};

/** 通知の中身（タイトルと本文）。端末の言語で作る */
function buildAlert(notice, lang) {
  const table = TEXT[lang] || TEXT.en;
  const type = notice.type;
  const make = table[type];
  if (!make) return null;
  const who = (notice.fromName || notice.fromCode || '').toString().slice(0, 60) || 'Difframe';
  // 中身（DM・コメントの文）は、ロック画面に出さない。誰からかだけを伝えて、アプリを開いて読んでもらう
  return { title: 'Difframe', body: make(who) };
}

/** APNs の認証トークン（ES256 の JWT）。.p8 の鍵で署名する */
function makeJWT(keyPem, keyId, teamId, nowSec = Math.floor(Date.now() / 1000)) {
  const b64 = v => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');
  const head = b64({ alg: 'ES256', kid: keyId });
  const body = b64({ iss: teamId, iat: nowSec });
  const signature = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: keyPem, dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${signature.toString('base64url')}`;
}

let cached = { jwt: '', at: 0 };
/** APNs は同じトークンを20分〜1時間使うよう求めている。50分ごとに作り直す */
function authToken(keyPem, keyId, teamId) {
  const now = Date.now();
  if (!cached.jwt || now - cached.at > 50 * 60 * 1000) cached = { jwt: makeJWT(keyPem, keyId, teamId), at: now };
  return cached.jwt;
}

/** APNs に1件送る。{ status, reason } を返す */
function sendToAPNs({ host, token, jwt, payload, collapseId }) {
  return new Promise(resolve => {
    const client = http2.connect(`https://${host}`);
    let settled = false;
    const done = result => { if (!settled) { settled = true; try { client.close(); } catch (e) { /* ignore */ } resolve(result); } };
    client.on('error', e => done({ status: 0, reason: String(e.message || e) }));
    const headers = {
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${jwt}`,
      'apns-topic': BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    };
    if (collapseId) headers['apns-collapse-id'] = collapseId.slice(0, 64);
    const req = client.request(headers);
    let status = 0;
    let data = '';
    req.setEncoding('utf8');
    req.on('response', h => { status = h[':status']; });
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => {
      let reason = '';
      try { reason = JSON.parse(data).reason || ''; } catch (e) { /* empty body on success */ }
      done({ status, reason });
    });
    req.on('error', e => done({ status: 0, reason: String(e.message || e) }));
    req.setTimeout(8000, () => { req.close(); done({ status: 0, reason: 'timeout' }); });
    req.end(JSON.stringify(payload));
  });
}

function hostFor(env) {
  return env === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
}

/**
 * 1人の端末（devices/{uid} の内容）にプッシュを送る。
 * 戻り値：'sent' | 'skipped' | 'invalid'（トークンが使えない＝消してよい） | 'failed'
 */
async function pushToDevice(device, notice, { keyPem, keyId, teamId, send = sendToAPNs }) {
  if (!device || !device.token) return 'skipped';
  const muted = Array.isArray(device.muted) ? device.muted : [];
  if (muted.includes(notice.type)) return 'skipped';
  const alert = buildAlert(notice, device.lang);
  if (!alert) return 'skipped';
  // タップしたときに、どの投稿・DM・友達を開くかを伝える（中身は入れない）
  const payload = {
    aps: { alert, sound: 'default', 'thread-id': notice.type },
    type: notice.type,
    postID: notice.postID || '',
    fromUID: notice.fromUID || '',
    fromName: String(notice.fromName || '').slice(0, 60),
    fromCode: String(notice.fromCode || '').slice(0, 40),
  };
  const jwt = authToken(keyPem, keyId, teamId);
  const collapseId = `${notice.type}_${notice.fromUID || ''}`;
  const first = device.env === 'sandbox' ? 'sandbox' : 'production';
  let result = await send({ host: hostFor(first), token: device.token, jwt, payload, collapseId });
  // 開発用/配布用の取り違えは、反対側でもう一度だけ試す
  if (result.status === 400 && result.reason === 'BadDeviceToken') {
    const other = first === 'sandbox' ? 'production' : 'sandbox';
    result = await send({ host: hostFor(other), token: device.token, jwt, payload, collapseId });
  }
  if (result.status === 200) return 'sent';
  if (result.status === 410 || (result.status === 400 && result.reason === 'BadDeviceToken') || result.reason === 'Unregistered') return 'invalid';
  console.warn('APNs failed', result.status, result.reason);
  return 'failed';
}

module.exports = { buildAlert, makeJWT, pushToDevice, hostFor, TEXT };

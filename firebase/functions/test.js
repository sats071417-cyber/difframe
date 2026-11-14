'use strict';
// サーバーの考え方（文面・署名・送り先の選び方）を、本物の APNs なしで確かめる
const assert = require('assert');
const crypto = require('crypto');
const { buildAlert, makeJWT, pushToDevice, hostFor } = require('./push');

(async () => {
  // 文面
  assert.deepStrictEqual(buildAlert({ type: 'friendPost', fromName: 'カンタ' }, 'ja'), { title: 'Difframe', body: 'カンタ さんが投稿しました' });
  assert.deepStrictEqual(buildAlert({ type: 'friendRequest', fromName: 'Kanta' }, 'en'), { title: 'Difframe', body: 'Kanta sent you a friend request' });
  // DM の中身は通知に出さない
  const dm = buildAlert({ type: 'message', fromName: 'Kanta', text: 'secret words' }, 'en');
  assert.deepStrictEqual(dm, { title: 'Difframe', body: 'Message from Kanta' });
  assert.ok(!JSON.stringify(dm).includes('secret words'));
  const cm = buildAlert({ type: 'comment', fromName: 'Kanta', text: 'private comment' }, 'ja');
  assert.ok(!JSON.stringify(cm).includes('private comment'));
  assert.strictEqual(buildAlert({ type: 'unknown' }, 'en'), null);
  assert.strictEqual(buildAlert({ type: 'like', fromName: 'A' }, 'xx').body, 'A reacted to your post');

  // JWT の署名が、公開鍵で確かめられる
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const jwt = makeJWT(pem, 'ABC123DEFG', '43346945VW', 1700000000);
  const [h, p, s] = jwt.split('.');
  assert.deepStrictEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: 'ABC123DEFG' });
  assert.deepStrictEqual(JSON.parse(Buffer.from(p, 'base64url')), { iss: '43346945VW', iat: 1700000000 });
  assert.ok(crypto.verify('sha256', Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')));

  const keys = { keyPem: pem, keyId: 'ABC123DEFG', teamId: '43346945VW' };
  const calls = [];
  const ok = async args => { calls.push(args); return { status: 200, reason: '' }; };
  const notice = { type: 'friendPost', fromName: 'カンタ', fromUID: 'u2', postID: 'u2_x' };

  // 送る（開発用の端末は sandbox へ）
  assert.strictEqual(await pushToDevice({ token: 'aa', env: 'sandbox', lang: 'ja', muted: [] }, notice, { ...keys, send: ok }), 'sent');
  assert.strictEqual(calls[0].host, 'api.sandbox.push.apple.com');
  assert.strictEqual(calls[0].payload.aps.alert.body, 'カンタ さんが投稿しました');
  assert.strictEqual(calls[0].payload.postID, 'u2_x');
  assert.strictEqual(calls[0].payload.fromUID, 'u2');
  assert.strictEqual(calls[0].payload.fromName, 'カンタ');
  // ミュート中・トークンなし
  assert.strictEqual(await pushToDevice({ token: 'aa', env: 'production', lang: 'ja', muted: ['friendPost'] }, notice, { ...keys, send: ok }), 'skipped');
  assert.strictEqual(await pushToDevice({ env: 'production' }, notice, { ...keys, send: ok }), 'skipped');
  // 開発用/配布用の取り違え：反対側で再送
  const seen = [];
  const wrongEnv = async a => { seen.push(a.host); return seen.length === 1 ? { status: 400, reason: 'BadDeviceToken' } : { status: 200, reason: '' }; };
  assert.strictEqual(await pushToDevice({ token: 'aa', env: 'production', lang: 'en' }, notice, { ...keys, send: wrongEnv }), 'sent');
  assert.deepStrictEqual(seen, [hostFor('production'), hostFor('sandbox')]);
  // 使えないトークン
  assert.strictEqual(await pushToDevice({ token: 'aa', env: 'production', lang: 'en' }, notice, { ...keys, send: async () => ({ status: 410, reason: 'Unregistered' }) }), 'invalid');
  // 一時的な失敗
  assert.strictEqual(await pushToDevice({ token: 'aa', env: 'production', lang: 'en' }, notice, { ...keys, send: async () => ({ status: 503, reason: 'ServiceUnavailable' }) }), 'failed');
  console.log('all push tests passed');
})().catch(e => { console.error(e); process.exit(1); });

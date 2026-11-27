'use strict';
// 連絡先から、Difframe を使っている友達を見つける。
//
// ・電話番号そのものは、サーバーに保存しない。
//   アプリは、番号（+81… の形）を SHA-256 にした値だけを送る。
//   サーバーは、それをさらに、サーバーだけが知っている鍵（PHONE_PEPPER）で HMAC にした値を、索引の名前にする。
//   索引（phoneIndex）と持ち主の記録（phoneOwners）は、アプリから読めない（ルールで全部断る）。
// ・自分の番号を索引に入れるのは、本人が「見つけてもらう」をオンにしたときだけ。
//   番号は Firebase Authentication で SMS 確認済みのものを使う（他人の番号を名乗れない）。
// ・連絡先の照合は、1回 1000 件まで、1日 5000 件まで。
const crypto = require('crypto');
const admin = require('firebase-admin');
const { HttpsError } = require('firebase-functions/v2/https');

const PER_CALL = 1000;
const PER_DAY = 5000;
const HEX64 = /^[0-9a-f]{64}$/;

const sha256 = text => crypto.createHash('sha256').update(text).digest('hex');
const indexKey = (pepper, hash) => crypto.createHmac('sha256', pepper).update(hash).digest('hex');

function requireUID(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'sign in first');
  return uid;
}

/** 自分の番号を、見つけてもらう索引に入れる（enabled: true）／外す（enabled: false） */
async function setDiscoverable(request, pepper) {
  const uid = requireUID(request);
  const enabled = request.data && request.data.enabled === true;
  const db = admin.firestore();
  const user = await admin.auth().getUser(uid);
  const phone = user.phoneNumber || '';
  const newKey = enabled && phone ? indexKey(pepper, sha256(phone)) : null;

  const ownerRef = db.doc(`phoneOwners/${uid}`);
  const owner = await ownerRef.get();
  const oldKey = owner.exists ? owner.get('key') : null;

  const batch = db.batch();
  if (oldKey && oldKey !== newKey) {
    const old = await db.doc(`phoneIndex/${oldKey}`).get();
    if (old.exists && old.get('uid') === uid) batch.delete(old.ref);
  }
  if (newKey) {
    batch.set(db.doc(`phoneIndex/${newKey}`), { uid, at: admin.firestore.FieldValue.serverTimestamp() });
    batch.set(ownerRef, { key: newKey });
  } else if (owner.exists) {
    batch.delete(ownerRef);
  }
  await batch.commit();
  return { discoverable: Boolean(newKey) };
}

/** 連絡先の番号（SHA-256）のうち、Difframe を使っていて、見つけてもらうをオンにしている人を返す */
async function matchContacts(request, pepper) {
  const uid = requireUID(request);
  const raw = Array.isArray(request.data && request.data.hashes) ? request.data.hashes : [];
  const hashes = [...new Set(raw.filter(h => typeof h === 'string' && HEX64.test(h)))];
  if (hashes.length === 0) return { matches: [] };
  if (hashes.length > PER_CALL) throw new HttpsError('invalid-argument', `at most ${PER_CALL} numbers per call`);

  // 電話番号を SMS で確認した人だけが探せる（使い捨てのアカウントで、たくさん試せないように）
  const me = await admin.auth().getUser(uid);
  if (!me.phoneNumber) throw new HttpsError('failed-precondition', 'verify your phone number first');

  const db = admin.firestore();
  // 1日の上限（たくさんの番号を当てずっぽうに試せないように）
  const today = new Date().toISOString().slice(0, 10);
  const quotaRef = db.doc(`contactQuota/${uid}`);
  await db.runTransaction(async tx => {
    const snap = await tx.get(quotaRef);
    const used = snap.exists && snap.get('day') === today ? snap.get('count') || 0 : 0;
    if (used + hashes.length > PER_DAY) throw new HttpsError('resource-exhausted', 'daily limit reached');
    tx.set(quotaRef, { day: today, count: used + hashes.length });
  });

  const refs = hashes.map(h => db.doc(`phoneIndex/${indexKey(pepper, h)}`));
  const found = [];
  for (let i = 0; i < refs.length; i += 100) {
    const docs = await db.getAll(...refs.slice(i, i + 100));
    docs.forEach((doc, j) => {
      if (doc.exists && doc.get('uid') !== uid) found.push({ hash: hashes[i + j], uid: doc.get('uid') });
    });
  }

  const matches = [];
  for (const m of found) {
    // 相手が自分をブロックしていたら、出さない
    const blocked = await db.doc(`blocks/${m.uid}/list/${uid}`).get();
    if (blocked.exists) continue;
    const profile = await db.doc(`profiles/${m.uid}`).get();
    if (!profile.exists) continue;
    const code = profile.get('code') || '';
    let handle = '';
    if (code) {
      const c = await db.doc(`codes/${code}`).get();
      if (c.exists && c.get('uid') === m.uid) handle = c.get('handle') || '';
    }
    matches.push({ hash: m.hash, uid: m.uid, code, name: profile.get('name') || '', handle });
  }
  return { matches };
}

/** アカウントが消えたら、索引からも外す */
async function cleanupOnDelete(uid) {
  const db = admin.firestore();
  const owner = await db.doc(`phoneOwners/${uid}`).get();
  if (!owner.exists) return;
  const key = owner.get('key');
  if (key) {
    const doc = await db.doc(`phoneIndex/${key}`).get();
    if (doc.exists && doc.get('uid') === uid) await doc.ref.delete();
  }
  await owner.ref.delete();
  await db.doc(`contactQuota/${uid}`).delete().catch(() => {});
}

module.exports = { setDiscoverable, matchContacts, cleanupOnDelete, sha256, indexKey };

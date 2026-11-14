'use strict';
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { pushToDevice } = require('./push');

admin.initializeApp();

// APNs の認証キー（.p8 の中身）。firebase functions:secrets:set APNS_KEY で入れる
const APNS_KEY = defineSecret('APNS_KEY');
const APNS_KEY_ID = defineString('APNS_KEY_ID');
const APNS_TEAM_ID = defineString('APNS_TEAM_ID', { default: '43346945VW' });

/**
 * 通知（友達リクエスト・友達になった・コメント・リアクション・友達の投稿・DM）が届いたら、
 * 受け取る人の端末にプッシュを送る。
 * 既読にしただけ（date が変わらない更新）では送らない。
 */
exports.pushOnNotice = onDocumentWritten(
  { document: 'notifications/{owner}/items/{item}', secrets: [APNS_KEY], region: process.env.FUNCTIONS_REGION || 'us-central1' },
  async event => {
    const after = event.data && event.data.after;
    if (!after || !after.exists) return;
    const notice = after.data();
    if (notice.read === true) return;
    const before = event.data.before;
    if (before && before.exists) {
      const a = before.data().date;
      const b = notice.date;
      if (a && b && a.isEqual(b)) return;
    }
    const owner = event.params.owner;
    if (notice.fromUID && notice.fromUID === owner) return;

    const deviceSnap = await admin.firestore().doc(`devices/${owner}`).get();
    if (!deviceSnap.exists) return;
    const outcome = await pushToDevice(deviceSnap.data(), notice, {
      keyPem: APNS_KEY.value(),
      keyId: APNS_KEY_ID.value(),
      teamId: APNS_TEAM_ID.value(),
    });
    if (outcome === 'invalid') {
      await deviceSnap.ref.delete().catch(() => {});
    }
  }
);

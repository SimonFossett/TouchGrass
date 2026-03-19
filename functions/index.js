const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// Returns "YYYY-MM-DD" for a given Date, using UTC.
function dateStr(d) {
  return d.toISOString().slice(0, 10);
}

/**
 * Runs every day at 00:01 UTC.
 *
 * Fix #9 – Streak race condition: instead of every client racing to write
 *   their own streak when they open the leaderboard, this function is the
 *   single authoritative source that decides who won each day.
 *
 * Fix #10 – Daily steps not resetting: regardless of whether a user opens
 *   the app, their Firestore dailySteps field is zeroed out at midnight so
 *   the leaderboard always shows accurate same-day numbers.
 */
exports.midnightReset = onSchedule("1 0 * * *", async () => {
  const now = new Date();

  // The day that just ended — this is what we're scoring.
  const yesterday = new Date(now);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const yesterdayStr = dateStr(yesterday);

  // Used to detect a consecutive-day streak.
  const twoDaysAgo = new Date(yesterday);
  twoDaysAgo.setUTCDate(twoDaysAgo.getUTCDate() - 1);
  const twoDaysAgoStr = dateStr(twoDaysAgo);

  // ── 1. Fetch every user ─────────────────────────────────────────────────
  const usersSnap = await db.collection("users").get();
  const users = {};
  usersSnap.forEach((doc) => {
    users[doc.id] = { id: doc.id, ...doc.data() };
  });

  // ── 2. Build uid → [friendUIDs] map from accepted friend requests ───────
  const friendsSnap = await db
    .collection("friendRequests")
    .where("status", "==", "accepted")
    .get();

  const friendMap = {}; // uid → string[]
  friendsSnap.forEach((doc) => {
    const { fromUID, toUID } = doc.data();
    if (!friendMap[fromUID]) friendMap[fromUID] = [];
    if (!friendMap[toUID]) friendMap[toUID] = [];
    friendMap[fromUID].push(toUID);
    friendMap[toUID].push(fromUID);
  });

  // ── 3. Score each user against their own friend group ──────────────────
  // Firestore batches are capped at 500 ops; we chunk automatically.
  let currentBatch = db.batch();
  const batches = [currentBatch];
  let opCount = 0;

  function batchUpdate(ref, data) {
    if (opCount > 0 && opCount % 499 === 0) {
      currentBatch = db.batch();
      batches.push(currentBatch);
    }
    currentBatch.update(ref, data);
    opCount++;
  }

  for (const uid of Object.keys(users)) {
    const user = users[uid];
    const friendUIDs = friendMap[uid] || [];
    const group = [user, ...friendUIDs.map((fid) => users[fid]).filter(Boolean)];

    const updates = {};

    // ── Daily streak ──────────────────────────────────────────────────────
    // Winner = highest dailySteps in the friend group (before today's reset).
    const dailyLeader = group.reduce((best, u) =>
      (u.dailySteps || 0) >= (best.dailySteps || 0) ? u : best
    );

    if (dailyLeader.id === uid && (user.dailySteps || 0) > 0) {
      const lastUpdated = user.dailyStreakLastUpdated || "";
      // Only award the streak once per day.
      if (lastUpdated !== yesterdayStr) {
        const prev = user.dailyStreak || 0;
        updates.dailyStreak = lastUpdated === twoDaysAgoStr ? prev + 1 : 1;
        updates.dailyStreakLastUpdated = yesterdayStr;
      }
    }

    // ── Overall streak ────────────────────────────────────────────────────
    // Winner = highest cumulative stepScore in the friend group.
    const overallLeader = group.reduce((best, u) =>
      (u.stepScore || 0) >= (best.stepScore || 0) ? u : best
    );

    if (overallLeader.id === uid && (user.stepScore || 0) > 0) {
      const lastUpdated = user.overallStreakLastUpdated || "";
      if (lastUpdated !== yesterdayStr) {
        const prev = user.overallStreak || 0;
        updates.overallStreak = lastUpdated === twoDaysAgoStr ? prev + 1 : 1;
        updates.overallStreakLastUpdated = yesterdayStr;
      }
    }

    // ── Reset dailySteps (fix #10) ────────────────────────────────────────
    // Zero out dailySteps for every user, whether or not they opened the app
    // today.  When users open the app the CMPedometer will push today's real
    // steps back, but until then the leaderboard correctly shows 0.
    updates.dailySteps = 0;

    batchUpdate(db.collection("users").doc(uid), updates);
  }

  await Promise.all(batches.map((b) => b.commit()));
  console.log(`midnightReset complete — updated ${opCount} user records.`);
});

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const nodemailer = require("nodemailer");

// SMTP credentials — set once with:
//   firebase functions:secrets:set SMTP_USER
//   firebase functions:secrets:set SMTP_PASS
const smtpUser = defineSecret("SMTP_USER");
const smtpPass = defineSecret("SMTP_PASS");

initializeApp();
const db = getFirestore();

// ── Push notification helper ──────────────────────────────────────────────────
async function sendNotification(token, title, body) {
  if (!token) return;
  try {
    await getMessaging().send({ token, notification: { title, body } });
  } catch (e) {
    console.error("[FCM] send error:", e.message);
  }
}

// ── Password reset email ──────────────────────────────────────────────────────
// Callable from the iOS app.  Generates a Firebase Auth password-reset link
// and delivers a branded TouchGrass email via SMTP (configured via secrets).
//
// Set credentials before deploying:
//   firebase functions:secrets:set SMTP_USER   (e.g. noreply@yourdomain.com)
//   firebase functions:secrets:set SMTP_PASS   (app password / API key)
//
// By default the function uses Gmail's SMTP.  Change `host`/`port`/`secure`
// in the transporter config below if you use a different provider
// (e.g. SendGrid: host smtp.sendgrid.net, port 587).
exports.sendPasswordResetEmail = onCall(
  { secrets: [smtpUser, smtpPass] },
  async (request) => {
    const email = (request.data?.email || "").trim().toLowerCase();
    if (!email) throw new HttpsError("invalid-argument", "Email is required.");

    // Generate the reset link via Firebase Admin Auth.
    // We catch user-not-found and return success anyway so callers can't
    // enumerate which emails are registered.
    let resetLink;
    try {
      resetLink = await getAuth().generatePasswordResetLink(email);
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        // Silently succeed — don't reveal whether the address is registered.
        return { success: true };
      }
      console.error("[PasswordReset] generatePasswordResetLink error:", err);
      throw new HttpsError("internal", "Failed to generate reset link.");
    }

    // ── HTML email template ──────────────────────────────────────────────────
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>Reset Your TouchGrass Password</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background-color:#f4f4f5;padding:48px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,0.08);">

          <!-- Header -->
          <tr>
            <td style="background-color:#16a34a;padding:36px 40px;text-align:center;">
              <div style="font-size:52px;line-height:1;margin-bottom:10px;">🚶</div>
              <h1 style="margin:0;color:#ffffff;font-size:26px;font-weight:700;letter-spacing:-0.3px;">TouchGrass</h1>
              <p style="margin:6px 0 0;color:#bbf7d0;font-size:14px;">Get outside. Stay active.</p>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding:40px 40px 32px;">
              <h2 style="margin:0 0 12px;color:#111827;font-size:20px;font-weight:600;">Reset your password</h2>
              <p style="margin:0 0 8px;color:#374151;font-size:15px;line-height:1.65;">
                Hi there,
              </p>
              <p style="margin:0 0 28px;color:#374151;font-size:15px;line-height:1.65;">
                We received a request to reset the password associated with this email address. If you made this request, click the button below to choose a new password.
              </p>

              <!-- CTA button -->
              <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
                <tr>
                  <td align="center" style="padding-bottom:32px;">
                    <a href="${resetLink}"
                       style="display:inline-block;background-color:#16a34a;color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;padding:14px 36px;border-radius:10px;letter-spacing:0.1px;">
                      Reset My Password
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin:0 0 6px;color:#6b7280;font-size:13px;line-height:1.6;">
                Button not working? Copy and paste this link into your browser:
              </p>
              <p style="margin:0 0 32px;font-size:12px;word-break:break-all;">
                <a href="${resetLink}" style="color:#16a34a;text-decoration:underline;">${resetLink}</a>
              </p>

              <hr style="border:none;border-top:1px solid #e5e7eb;margin:0 0 24px;">

              <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
                <tr>
                  <td width="20" valign="top" style="padding-top:1px;">
                    <span style="font-size:15px;">⏱</span>
                  </td>
                  <td style="color:#6b7280;font-size:13px;line-height:1.65;padding-left:8px;">
                    <strong style="color:#374151;">This link expires in 1 hour.</strong> After that you'll need to request a new one.
                  </td>
                </tr>
                <tr><td colspan="2" style="padding:8px 0;"></td></tr>
                <tr>
                  <td width="20" valign="top" style="padding-top:1px;">
                    <span style="font-size:15px;">🔒</span>
                  </td>
                  <td style="color:#6b7280;font-size:13px;line-height:1.65;padding-left:8px;">
                    For security, this link can only be used once. Your current password remains unchanged until you complete the reset.
                  </td>
                </tr>
                <tr><td colspan="2" style="padding:8px 0;"></td></tr>
                <tr>
                  <td width="20" valign="top" style="padding-top:1px;">
                    <span style="font-size:15px;">🤔</span>
                  </td>
                  <td style="color:#6b7280;font-size:13px;line-height:1.65;padding-left:8px;">
                    Didn't request this? You can safely ignore this email — your account is secure and no changes have been made.
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color:#f9fafb;padding:24px 40px;border-top:1px solid #e5e7eb;text-align:center;">
              <p style="margin:0 0 4px;color:#9ca3af;font-size:12px;line-height:1.6;">
                © ${new Date().getFullYear()} TouchGrass. All rights reserved.
              </p>
              <p style="margin:0;color:#9ca3af;font-size:12px;line-height:1.6;">
                You're receiving this email because a password reset was requested for your account.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

    // ── Send via SMTP ────────────────────────────────────────────────────────
    const transporter = nodemailer.createTransport({
      host: "smtp.gmail.com",
      port: 465,
      secure: true,
      auth: {
        user: smtpUser.value(),
        pass: smtpPass.value(),
      },
    });

    try {
      await transporter.sendMail({
        from: `"TouchGrass" <${smtpUser.value()}>`,
        to: email,
        subject: "Reset Your TouchGrass Password",
        html,
      });
    } catch (err) {
      console.error("[PasswordReset] sendMail error:", err);
      throw new HttpsError("internal", "Failed to send reset email.");
    }

    return { success: true };
  }
);

// ── 0. Step-score rate-limit / anti-spoof ────────────────────────────────────
// Fires on every user-document write. Validates that stepScore and dailySteps
// didn't jump by more than a physically possible amount since the last write.
//
// Algorithm:
//   maxAllowed = min(elapsedSeconds * 10 steps/sec, 50 000 steps)
//   (10 steps/sec ≈ 3× the world-record walking pace, giving a generous buffer)
// When elapsed time is unknown (first ever write) we allow up to 50 000 steps.
//
// On a violation the field is reverted to its previous value and a warning is
// logged.  The server-set *LastValidated timestamps are what make this
// tamper-proof – clients cannot forge them.
exports.validateStepUpdate = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data?.before?.data();
  const after  = event.data?.after?.data();
  if (!before || !after) return;

  const uid = event.params.uid;
  const ref = event.data.after.ref;
  const now = Date.now();

  // Max steps a human can accumulate per second (very generous upper bound).
  const MAX_STEPS_PER_SECOND = 10;
  // Hard per-update cap regardless of elapsed time (~50 000 steps ≈ a full
  // ultramarathon day; impossible to accumulate between two app writes).
  const MAX_STEPS_PER_UPDATE = 50000;

  const updates = {};

  function checkField(field, lastUpdatedField) {
    const oldVal = before[field] ?? 0;
    const newVal = after[field]  ?? 0;
    if (newVal <= oldVal) return; // decreases and no-ops are fine

    const increase   = newVal - oldVal;
    const lastMs     = before[lastUpdatedField]?.toMillis?.() ?? null;
    const elapsedSec = lastMs !== null
      ? Math.max(1, (now - lastMs) / 1000)
      : null; // unknown — first write

    const maxAllowed = elapsedSec !== null
      ? Math.min(elapsedSec * MAX_STEPS_PER_SECOND, MAX_STEPS_PER_UPDATE)
      : MAX_STEPS_PER_UPDATE;

    if (increase > maxAllowed) {
      updates[field] = oldVal; // revert
      console.warn(
        `[RateLimit] ${uid} ${field} spike: +${increase} steps` +
        (elapsedSec !== null ? ` in ${elapsedSec.toFixed(0)}s` : " (first write)") +
        ` (max allowed: ${Math.round(maxAllowed)})`
      );
    } else {
      updates[lastUpdatedField] = FieldValue.serverTimestamp();
    }
  }

  checkField("stepScore",  "stepScoreLastValidated");
  checkField("dailySteps", "dailyStepsLastValidated");

  if (Object.keys(updates).length > 0) {
    await ref.update(updates);
  }
});

// ── 1. Friend request notification ───────────────────────────────────────────
// Fires when a new friendRequest document is created with status "pending".
exports.onFriendRequest = onDocumentCreated("friendRequests/{docId}", async (event) => {
  const data = event.data?.data();
  if (!data || data.status !== "pending") return;

  const [recipientSnap, senderSnap] = await Promise.all([
    db.collection("users").doc(data.toUID).get(),
    db.collection("users").doc(data.fromUID).get(),
  ]);

  const token = recipientSnap.data()?.fcmToken;
  const senderName = senderSnap.data()?.username || "Someone";
  await sendNotification(token, "New Friend Request", `${senderName} wants to connect!`);
});

// ── 2. Leaderboard overtaken notification ────────────────────────────────────
// Fires whenever a user document changes. If their dailySteps increased and
// they now lead a friend who was previously ahead, notify that friend.
exports.onStepsUpdate = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data?.before?.data();
  const after  = event.data?.after?.data();
  if (!before || !after) return;

  const newSteps = after.dailySteps  || 0;
  const oldSteps = before.dailySteps || 0;
  if (newSteps <= oldSteps) return; // only act on increases

  const uid = event.params.uid;
  const updaterName = after.username || "A friend";

  // Fetch all accepted friend requests involving this user
  const [fromSnap, toSnap] = await Promise.all([
    db.collection("friendRequests").where("fromUID", "==", uid).where("status", "==", "accepted").get(),
    db.collection("friendRequests").where("toUID",   "==", uid).where("status", "==", "accepted").get(),
  ]);

  const friendUIDs = [];
  fromSnap.forEach((doc) => friendUIDs.push(doc.data().toUID));
  toSnap.forEach((doc)   => friendUIDs.push(doc.data().fromUID));

  for (const fid of friendUIDs) {
    const friendSnap = await db.collection("users").doc(fid).get();
    const friendData = friendSnap.data();
    if (!friendData?.fcmToken) continue;

    const friendSteps = friendData.dailySteps || 0;
    // Friend was ahead before (or tied) and is now behind — they've been overtaken
    if (oldSteps <= friendSteps && newSteps > friendSteps) {
      await sendNotification(
        friendData.fcmToken,
        "You've been overtaken! 🏃",
        `${updaterName} just passed you on today's leaderboard!`
      );
    }
  }
});

// ── 3. Streak-at-risk reminder (22:00 UTC = 2 h before midnight reset) ───────
exports.streakRiskReminder = onSchedule("0 22 * * *", async () => {
  const usersSnap = await db.collection("users").get();
  const users = {};
  usersSnap.forEach((doc) => { users[doc.id] = { id: doc.id, ...doc.data() }; });

  const friendsSnap = await db.collection("friendRequests").where("status", "==", "accepted").get();
  const friendMap = {};
  friendsSnap.forEach((doc) => {
    const { fromUID, toUID } = doc.data();
    if (!friendMap[fromUID]) friendMap[fromUID] = [];
    if (!friendMap[toUID])   friendMap[toUID]   = [];
    friendMap[fromUID].push(toUID);
    friendMap[toUID].push(fromUID);
  });

  for (const uid of Object.keys(users)) {
    const user = users[uid];
    if ((user.dailyStreak || 0) === 0) continue; // no streak to protect
    if (!user.fcmToken) continue;

    const friendUIDs = friendMap[uid] || [];
    const group = [user, ...friendUIDs.map((fid) => users[fid]).filter(Boolean)];

    const dailyLeader = group.reduce((best, u) =>
      (u.dailySteps || 0) >= (best.dailySteps || 0) ? u : best
    );

    if (dailyLeader.id !== uid) {
      await sendNotification(
        user.fcmToken,
        "Streak at Risk! 🔥",
        `Your ${user.dailyStreak}-day streak is in danger! Walk more to protect it!`
      );
    }
  }
  console.log("streakRiskReminder complete.");
});

// Returns "YYYY-MM-DD" for a given Date, using UTC.
function dateStr(d) {
  return d.toISOString().slice(0, 10);
}

/**
 * Runs every day at 00:01 UTC.
 *
 * Single authoritative source for streak evaluation and daily reset:
 *   - Reads every user's step count for the day that just ended.
 *   - For each user, compares against their entire friend group.
 *   - Sole #1 (most steps, > 0, no tie) → streak increments.
 *   - Everyone else → streak resets to 0.
 *   - Archives steps to stepHistory and zeroes dailySteps for all users.
 *
 * Timezone note: runs at 00:01 UTC. Users in UTC+ timezones may have already
 * had their local midnight fire on the iOS client, which writes stepHistory
 * before resetting dailySteps to 0. The resolveSteps() helper reads
 * stepHistory as a fallback so those users' steps are never lost.
 */
exports.midnightReset = onSchedule("1 0 * * *", async () => {
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const yesterdayStr = dateStr(yesterday);
  const todayStr = dateStr(now);

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

  const friendMap = {};
  friendsSnap.forEach((doc) => {
    const { fromUID, toUID } = doc.data();
    if (!friendMap[fromUID]) friendMap[fromUID] = [];
    if (!friendMap[toUID])   friendMap[toUID]   = [];
    friendMap[fromUID].push(toUID);
    friendMap[toUID].push(fromUID);
  });

  // ── 3. Score each user against their friend group ───────────────────────
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

  // Returns the step count for the day just ended.
  // Primary: dailySteps (still populated for users who haven't hit local midnight yet).
  // Fallback: stepHistory[yesterday] (written by the iOS client when local midnight
  //   fires before 00:01 UTC, i.e. users in UTC+ timezones).
  function resolveSteps(u) {
    const direct = u.dailySteps || 0;
    if (direct > 0) return direct;
    return (u.stepHistory || {})[yesterdayStr] || 0;
  }

  for (const uid of Object.keys(users)) {
    const user = users[uid];
    const friendUIDs = friendMap[uid] || [];
    const group = [user, ...friendUIDs.map((fid) => users[fid]).filter(Boolean)];

    // Collect step totals for every participant in this user's friend group.
    const groupSteps = group.map((u) => ({ uid: u.id, steps: resolveSteps(u) }));
    const maxSteps = Math.max(0, ...groupSteps.map((g) => g.steps));

    // Strict #1: sole leader with > 0 steps. Ties produce no winner.
    const leaders = maxSteps > 0 ? groupSteps.filter((g) => g.steps === maxSteps) : [];
    const winnerUID = leaders.length === 1 ? leaders[0].uid : null;

    const mySteps = resolveSteps(user);
    const updates = {};

    // Every user gets an explicit streak write — no silent skips.
    // This is what ensures losers (including tied users) always reset to 0.
    updates.dailyStreak = winnerUID === uid ? (user.dailyStreak || 0) + 1 : 0;

    // Archive to stepHistory before zeroing (only when client hasn't already written it).
    if (mySteps > 0) {
      const existing = (user.stepHistory || {})[yesterdayStr] || 0;
      if (mySteps > existing) {
        updates[`stepHistory.${yesterdayStr}`] = mySteps;
      }
    }

    // ── Leaderboard placement stats ──────────────────────────────────────────
    // Standard competitive ranking: count members with strictly more steps to
    // get the user's 1-based rank (ties share the same rank).
    // Idempotency guard: leaderboardStatsDate tracks the last day we updated
    // these counters, preventing double-counting if the function re-runs.
    if (user.leaderboardStatsDate !== yesterdayStr && mySteps > 0) {
      const rank = groupSteps.filter((g) => g.steps > mySteps).length + 1;
      if (rank === 1)      updates["leaderboardStats.firstPlace"]  = FieldValue.increment(1);
      else if (rank === 2) updates["leaderboardStats.secondPlace"] = FieldValue.increment(1);
      else if (rank === 3) updates["leaderboardStats.thirdPlace"]  = FieldValue.increment(1);
      updates.leaderboardStatsDate = yesterdayStr;
    }

    // Reset for the new day — applies to every user regardless of app activity.
    updates.dailySteps = 0;
    updates.dailyStepsDate = todayStr;

    batchUpdate(db.collection("users").doc(uid), updates);
  }

  await Promise.all(batches.map((b) => b.commit()));
  console.log(`midnightReset complete — ${opCount} user records updated.`);
});

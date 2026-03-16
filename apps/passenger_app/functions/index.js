const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const PAYMENT_PORTAL_SECRET = defineSecret("PAYMENT_PORTAL_SECRET");
const PAYMENT_PORTAL_PAT = defineSecret("PAYMENT_PORTAL_PAT");
const PAYMENT_PORTAL_KEY = defineSecret("PAYMENT_PORTAL_KEY");
const PAYMENT_PORTAL_CHARGE_URL = defineString("PAYMENT_PORTAL_CHARGE_URL");
const PAYMENT_PORTAL_PAYMENT_CHANNEL = defineString("PAYMENT_PORTAL_PAYMENT_CHANNEL");
const PAYMENT_PORTAL_BANKS_URL = defineString("PAYMENT_PORTAL_BANKS_URL");
const PAYMENT_PORTAL_RETURN_URL = defineString("PAYMENT_PORTAL_RETURN_URL");
const PAYMENT_PORTAL_CALLBACK_URL = defineString("PAYMENT_PORTAL_CALLBACK_URL");

const COLLECTIONS = {
  bookings: "bookings",
  operatorPresence: "operator_presence",
  operatorDevices: "operator_devices",
  userDevices: "user_devices",
};

const BOOKING_FIELDS = {
  bookingId: "bookingId",
  userId: "userId",
  status: "status",
  origin: "origin",
  destination: "destination",
  driverId: "driverId",
  updatedAt: "updatedAt",
    passengerCount: "passengerCount",
};

const DEVICE_FIELDS = {
  token: "token",
  appRole: "appRole",
};

exports.getDobwBanks = onCall(
  {
    region: "asia-southeast1",
    secrets: [PAYMENT_PORTAL_PAT],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const pat = PAYMENT_PORTAL_PAT.value();
    const banksUrl = PAYMENT_PORTAL_BANKS_URL.value();
    if (!pat || !pat.trim()) {
      throw new HttpsError(
        "failed-precondition",
        "PAYMENT_PORTAL_PAT is not configured."
      );
    }
    if (!banksUrl || !banksUrl.trim()) {
      throw new HttpsError(
        "failed-precondition",
        "PAYMENT_PORTAL_BANKS_URL is not configured."
      );
    }

    const upstream = await fetch(banksUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${pat}`,
      },
    });

    let payload = {};
    try {
      payload = await upstream.json();
    } catch (_) {
      payload = {};
    }

    if (!upstream.ok) {
      logger.error("BayarCash banks API error", {
        code: upstream.status,
        payload,
      });
      throw new HttpsError("internal", "Unable to load payment bank list.");
    }

    const candidates =
      (Array.isArray(payload) && payload) ||
      payload.data ||
      payload.banks ||
      [];

    const banks = (Array.isArray(candidates) ? candidates : [])
      .map((item) => ({
        code: String(item.bank_code || item.code || item.payer_bank_code || ""),
        name: String(item.bank_name || item.name || item.payer_bank_name || ""),
      }))
      .filter((b) => b.code && b.name);

    return { banks };
  }
);

exports.createPaymentCharge = onCall(
  {
    region: "asia-southeast1",
    secrets: [PAYMENT_PORTAL_SECRET, PAYMENT_PORTAL_PAT, PAYMENT_PORTAL_KEY],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const data = request.data || {};
    const amount = Number(data.amount || 0);
    const currency = String(data.currency || "").trim();
    const orderNumber = String(data.orderNumber || "").trim();
    const payerName = String(data.payerName || "").trim();
    const payerEmail = String(data.payerEmail || "").trim();
    const payerTelephoneNumber = String(data.payerTelephoneNumber || "").trim();
    const payerBankCode = String(data.payerBankCode || "").trim();
    const payerBankName = String(data.payerBankName || "").trim();
    const paymentMethod = String(data.paymentMethod || "").trim();
    const idempotencyKey = String(data.idempotencyKey || "").trim();
    const description = String(data.description || "").trim();

    if (
      !(amount > 0) ||
      !currency ||
      !orderNumber ||
      !payerName ||
      !payerEmail ||
      !paymentMethod ||
      !idempotencyKey
    ) {
      throw new HttpsError(
        "invalid-argument",
        "amount, currency, orderNumber, payerName, payerEmail, paymentMethod, and idempotencyKey are required."
      );
    }

    const secret = PAYMENT_PORTAL_SECRET.value();
    const pat = PAYMENT_PORTAL_PAT.value();
    const portalKey = PAYMENT_PORTAL_KEY.value();

    if (!pat || !pat.trim()) {
      throw new HttpsError(
        "failed-precondition",
        "PAYMENT_PORTAL_PAT is not configured."
      );
    }
    if (!portalKey || !portalKey.trim()) {
      throw new HttpsError(
        "failed-precondition",
        "PAYMENT_PORTAL_KEY is not configured."
      );
    }

    // Keep secret configured for optional checksum/signature integration.
    if (!secret || !secret.trim()) {
      logger.warn("PAYMENT_PORTAL_SECRET is empty; checksum/signature is disabled.");
    }

    const chargeUrl = PAYMENT_PORTAL_CHARGE_URL.value();
    const paymentChannelRaw = PAYMENT_PORTAL_PAYMENT_CHANNEL.value();
    const paymentChannel = Number(paymentChannelRaw || "5");
    const returnUrl = PAYMENT_PORTAL_RETURN_URL.value();
    const callbackUrl = PAYMENT_PORTAL_CALLBACK_URL.value();
    if (chargeUrl) {
      const headers = {
        "Content-Type": "application/json",
        Authorization: `Bearer ${pat}`,
        "Idempotency-Key": idempotencyKey,
      };

      const upstream = await fetch(chargeUrl, {
        method: "POST",
        headers,
        body: JSON.stringify({
          payment_channel: paymentChannel,
          portal_key: portalKey,
          order_number: orderNumber,
          amount,
          payer_name: payerName,
          payer_email: payerEmail,
          payer_telephone_number: payerTelephoneNumber || undefined,
          payer_bank_code: payerBankCode || undefined,
          payer_bank_name: payerBankName || undefined,
          metadata: description || undefined,
          return_url: returnUrl || undefined,
          callback_url: callbackUrl || undefined,
          platform_id: request.auth.uid,
          checksum: undefined,
        }),
      });

      let payload = {};
      try {
        payload = await upstream.json();
      } catch (_) {
        payload = {};
      }

      if (!upstream.ok) {
        logger.error("Payment gateway error", {
          code: upstream.status,
          payload,
        });
        throw new HttpsError(
          "internal",
          "Payment gateway rejected the transaction."
        );
      }

      return {
        status: "success",
        transactionId:
          payload.transactionId || payload.id || `tx-${Date.now()}`,
        redirectUrl: payload.url || payload.redirect_url || null,
        message: "Charge successful",
      };
    }

    logger.warn(
      "PAYMENT_PORTAL_CHARGE_URL not set. Returning server-side simulated charge."
    );

    return {
      status: "success",
      transactionId: `srv-sim-${Date.now()}-${Math.floor(Math.random() * 1000000)}`,
      message: "Simulated server-side charge successful",
    };
  }
);

exports.bayarcashWebhook = onRequest(
  {
    region: "asia-southeast1",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      const payload = req.body || {};
      const reference = String(
        payload.id || payload.transaction_id || payload.reference || ""
      );
      const status = String(payload.status || payload.payment_status || "unknown");
      const idempotencyKey = String(
        payload.idempotency_key || payload?.metadata?.idempotencyKey || ""
      );

      await db.collection("payment_webhooks").add({
        provider: "bayarcash",
        reference,
        status,
        idempotencyKey,
        payload,
        receivedAt: new Date(),
      });

      // Always return 200 after durable write so provider retries stop.
      res.status(200).json({ ok: true });
    } catch (error) {
      logger.error("Webhook processing failed", error);
      // Return 500 to allow provider retry if processing fails.
      res.status(500).json({ error: "Webhook processing failed" });
    }
  }
);

exports.notifyOperatorsOnIncomingBooking = onDocumentCreated(
  {
    document: "bookings/{bookingId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      return;
    }

    if (data[BOOKING_FIELDS.status] !== "pending") {
      return;
    }

    const bookingId = data[BOOKING_FIELDS.bookingId] || event.params.bookingId;
    const origin = data[BOOKING_FIELDS.origin] || "Unknown origin";
    const destination = data[BOOKING_FIELDS.destination] || "Unknown destination";

    const onlineOperatorIds = await getOnlineOperatorIds();
    if (onlineOperatorIds.length === 0) {
      logger.info("No online operators for incoming booking", { bookingId });
      return;
    }

    const tokens = await getOperatorTokens(onlineOperatorIds);
    if (tokens.length === 0) {
      logger.info("No operator tokens for online operators", { bookingId });
      return;
    }

    await sendMulticastAndCleanup({
      tokens,
      notification: {
        title: "Incoming booking request",
        body: `${origin} to ${destination}`,
      },
      data: {
        type: "incoming_booking",
        bookingId: String(bookingId),
        status: "pending",
      },
      tokenCollection: COLLECTIONS.operatorDevices,
    });
  }
);

exports.notifyBookingStatusChanged = onDocumentUpdated(
  {
    document: "bookings/{bookingId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) {
      return;
    }

    const previousStatus = before[BOOKING_FIELDS.status] || "unknown";
    const newStatus = after[BOOKING_FIELDS.status] || "unknown";

    if (previousStatus === newStatus) {
      return;
    }

    const bookingId = after[BOOKING_FIELDS.bookingId] || event.params.bookingId;
    const origin = after[BOOKING_FIELDS.origin] || "Unknown origin";
    const destination = after[BOOKING_FIELDS.destination] || "Unknown destination";
    const userId = after[BOOKING_FIELDS.userId];
    const operatorId = after[BOOKING_FIELDS.driverId];
     const passengerCount = String(after[BOOKING_FIELDS.passengerCount] || 1);

    const passengerToken = userId
      ? await getDeviceToken(COLLECTIONS.userDevices, userId, "passenger")
      : null;

    if (passengerToken) {
      await sendMulticastAndCleanup({
        tokens: [passengerToken],
        notification: {
          title: "Booking status updated",
          body: `${origin} to ${destination}: ${statusLabel(newStatus)}`,
        },
        data: {
          type: "booking_status",
          bookingId: String(bookingId),
          status: String(newStatus),
           origin: String(origin),
           destination: String(destination),
           passengerCount,
        },
        tokenCollection: COLLECTIONS.userDevices,
      });
    }

    if (operatorId) {
      const operatorToken = await getDeviceToken(
        COLLECTIONS.operatorDevices,
        operatorId,
        "operator"
      );

      if (operatorToken) {
        await sendMulticastAndCleanup({
          tokens: [operatorToken],
          notification: {
            title: "Booking status updated",
            body: `${bookingId}: ${statusLabel(newStatus)}`,
          },
          data: {
            type: "booking_status",
            bookingId: String(bookingId),
            status: String(newStatus),
          },
          tokenCollection: COLLECTIONS.operatorDevices,
        });
      }
    }

  }
);

async function getOnlineOperatorIds() {
  const snapshot = await db
    .collection(COLLECTIONS.operatorPresence)
    .where("isOnline", "==", true)
    .get();

  return snapshot.docs.map((doc) => doc.id);
}

async function getOperatorTokens(operatorIds) {
  const tokens = [];

  for (const operatorId of operatorIds) {
    const token = await getDeviceToken(
      COLLECTIONS.operatorDevices,
      operatorId,
      "operator"
    );
    if (token) {
      tokens.push(token);
    }
  }

  return tokens;
}

async function getDeviceToken(collection, documentId, expectedRole) {
  const snapshot = await db.collection(collection).doc(documentId).get();
  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data();
  const token = data?.[DEVICE_FIELDS.token];
  const role = data?.[DEVICE_FIELDS.appRole];

  if (!token || role !== expectedRole) {
    return null;
  }

  return token;
}

async function sendMulticastAndCleanup({ tokens, notification, data, tokenCollection }) {
  if (tokens.length === 0) {
    return;
  }

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification,
    data,
    android: {
      priority: "high",
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
    },
  });

  const cleanupTasks = [];
  response.responses.forEach((result, index) => {
    if (result.success || !result.error) {
      return;
    }

    const code = result.error.code || "";
    const invalidToken =
      code.includes("registration-token-not-registered") ||
      code.includes("invalid-registration-token");

    if (!invalidToken) {
      return;
    }

    const token = tokens[index];
    cleanupTasks.push(removeTokenByValue(tokenCollection, token));
  });

  await Promise.all(cleanupTasks);
}

async function removeTokenByValue(collection, token) {
  const snapshot = await db
    .collection(collection)
    .where(DEVICE_FIELDS.token, "==", token)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return;
  }

  await snapshot.docs[0].ref.delete();
}

function statusLabel(status) {
  switch (status) {
    case "pending":
      return "Waiting for operator";
    case "accepted":
      return "Accepted by operator";
    case "on_the_way":
      return "Operator is on the way";
    case "completed":
      return "Trip completed";
    case "cancelled":
      return "Booking cancelled";
    case "rejected":
      return "No operator available";
    default:
      return String(status).replaceAll("_", " ");
  }
}

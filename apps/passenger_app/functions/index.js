const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const Stripe = require("stripe");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_CURRENCY = defineString("STRIPE_CURRENCY");

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
  operatorId: "operatorId",
  legacyDriverId: "driverId",
  updatedAt: "updatedAt",
  passengerCount: "passengerCount",
  paymentStatus: "paymentStatus",
  orderNumber: "orderNumber",
  transactionId: "transactionId",
};

const DEVICE_FIELDS = {
  token: "token",
  appRole: "appRole",
};

exports.createStripePaymentIntent = onCall(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const data = request.data || {};
    const amount = Number(data.amount || 0);
    const currencyRaw = String(data.currency || "").trim().toLowerCase();
    const defaultCurrency = String(STRIPE_CURRENCY.value() || "myr").trim().toLowerCase();
    const currency = currencyRaw || defaultCurrency || "myr";
    const orderNumber = String(data.orderNumber || "").trim();
    const payerName = String(data.payerName || "").trim();
    const payerEmail = String(data.payerEmail || "").trim();
    const payerTelephoneNumber = String(data.payerTelephoneNumber || "").trim();
    const idempotencyKey = String(data.idempotencyKey || "").trim();
    const description = String(data.description || "").trim();

    if (!(amount > 0) || !currency || !orderNumber || !payerName || !payerEmail || !idempotencyKey) {
      throw new HttpsError(
        "invalid-argument",
        "amount, currency, orderNumber, payerName, payerEmail, and idempotencyKey are required."
      );
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      throw new HttpsError("failed-precondition", "STRIPE_SECRET_KEY is not configured.");
    }

    const stripe = new Stripe(secretKey);
    const amountInMinorUnit = Math.round(amount * 100);
    if (!(amountInMinorUnit > 0)) {
      throw new HttpsError("invalid-argument", "amount must be at least 0.01.");
    }

    try {
      const intent = await stripe.paymentIntents.create(
        {
          amount: amountInMinorUnit,
          currency,
          capture_method: 'manual',  // ← ADD THIS LINE
          receipt_email: payerEmail,
          description: description || `Water taxi booking ${orderNumber}`,
          automatic_payment_methods: { enabled: true },
          metadata: {
            userId: request.auth.uid,
            orderNumber,
            payerName,
            payerTelephoneNumber,
            idempotencyKey,
          },
        },
        {
          idempotencyKey,
        }
      );

      logger.info("Stripe payment intent created", {
        paymentIntentId: intent.id,
        orderNumber,
        amountInMinorUnit,
        currency,
      });

      return {
        status: "ready",
        paymentIntentId: intent.id,
        clientSecret: intent.client_secret,
      };
    } catch (error) {
      logger.error("Stripe payment intent creation failed", {
        message: error?.message || "Unknown Stripe error",
        orderNumber,
      });
      throw new HttpsError("internal", "Unable to initialize Stripe payment.");
    }
  }
);

exports.createStripePaymentIntentHttp = onRequest(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      const authHeader = String(req.headers.authorization || "");
      if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ status: "failed", message: "Unauthorized" });
        return;
      }

      const idToken = authHeader.substring("Bearer ".length).trim();
      let decoded;
      try {
        decoded = await getAuth().verifyIdToken(idToken);
      } catch (authError) {
        logger.warn("createStripePaymentIntentHttp invalid Firebase ID token", {
          message: authError?.message || "Unknown auth verification error",
        });
        res.status(401).json({
          status: "failed",
          message: "Invalid authentication token. Please sign in again.",
        });
        return;
      }

      const data = req.body || {};
      const amount = Number(data.amount || 0);
      const currencyRaw = String(data.currency || "").trim().toLowerCase();
      const defaultCurrency = String(STRIPE_CURRENCY.value() || "myr").trim().toLowerCase();
      const currency = currencyRaw || defaultCurrency || "myr";
      const orderNumber = String(data.orderNumber || "").trim();
      const payerName = String(data.payerName || "").trim();
      const payerEmail = String(data.payerEmail || "").trim();
      const payerTelephoneNumber = String(data.payerTelephoneNumber || "").trim();
      const idempotencyKey = String(data.idempotencyKey || "").trim();
      const description = String(data.description || "").trim();

      if (!(amount > 0) || !currency || !orderNumber || !payerName || !payerEmail || !idempotencyKey) {
        res.status(400).json({
          status: "failed",
          message:
            "amount, currency, orderNumber, payerName, payerEmail, and idempotencyKey are required.",
        });
        return;
      }

      const secretKey = STRIPE_SECRET_KEY.value();
      if (!secretKey || !secretKey.trim()) {
        res.status(500).json({ status: "failed", message: "STRIPE_SECRET_KEY is not configured." });
        return;
      }

      const stripe = new Stripe(secretKey);
      const amountInMinorUnit = Math.round(amount * 100);
      if (!(amountInMinorUnit > 0)) {
        res.status(400).json({ status: "failed", message: "amount must be at least 0.01." });
        return;
      }

      const intent = await stripe.paymentIntents.create(
        {
          amount: amountInMinorUnit,
          currency,
          capture_method: "manual",
          receipt_email: payerEmail,
          description: description || `Water taxi booking ${orderNumber}`,
          automatic_payment_methods: { enabled: true },
          metadata: {
            userId: decoded.uid,
            orderNumber,
            payerName,
            payerTelephoneNumber,
            idempotencyKey,
          },
        },
        {
          idempotencyKey,
        }
      );

      res.status(200).json({
        status: "ready",
        paymentIntentId: intent.id,
        clientSecret: intent.client_secret,
      });
    } catch (error) {
      const message =
        error?.raw?.message ||
        error?.message ||
        (typeof error === "string" ? error : "Unknown error");
      const type = error?.type || "unknown";
      const code = error?.code || "unknown";

      logger.error("createStripePaymentIntentHttp failed", {
        message,
        type,
        code,
        stack: error?.stack || null,
      });
      res.status(500).json({
        status: "failed",
        message: `Unable to initialize Stripe payment: ${message}`,
      });
    }
  }
);

exports.stripeWebhook = onRequest(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      logger.error("stripeWebhook called without STRIPE_SECRET_KEY configured");
      res.status(500).json({ error: "Stripe not configured" });
      return;
    }

    const stripe = new Stripe(secretKey);
    const webhookSecret = String(process.env.STRIPE_WEBHOOK_SECRET || "").trim();

    try {
      let event;
      if (webhookSecret) {
        const signature = req.headers["stripe-signature"];
        event = stripe.webhooks.constructEvent(req.rawBody, signature, webhookSecret);
      } else {
        event = req.body;
      }

      const eventType = String(event?.type || "unknown");
      const payloadObject = event?.data?.object || {};
      const paymentIntentId = String(payloadObject.id || "");
      const status = String(payloadObject.status || "unknown");
      const orderNumber = String(payloadObject?.metadata?.orderNumber || "");

      await db.collection("payment_webhooks").add({
        provider: "stripe",
        eventType,
        paymentIntentId,
        status,
        orderNumber,
        payload: event,
        receivedAt: new Date(),
      });

      if (eventType === "payment_intent.succeeded" && orderNumber) {
        const snapshot = await db
          .collection(COLLECTIONS.bookings)
          .where(BOOKING_FIELDS.orderNumber, "==", orderNumber)
          .limit(1)
          .get();

        if (!snapshot.empty) {
          await snapshot.docs[0].ref.update({
            [BOOKING_FIELDS.paymentStatus]: "paid",
            [BOOKING_FIELDS.transactionId]: paymentIntentId,
            [BOOKING_FIELDS.updatedAt]: new Date(),
          });
        }
      }

      if (eventType === "payment_intent.amount.capturably_held" && orderNumber) {
        const snapshot = await db
          .collection(COLLECTIONS.bookings)
          .where(BOOKING_FIELDS.orderNumber, "==", orderNumber)
          .limit(1)
          .get();

        if (!snapshot.empty) {
          await snapshot.docs[0].ref.update({
            [BOOKING_FIELDS.paymentStatus]: "authorized",
            [BOOKING_FIELDS.transactionId]: paymentIntentId,
            [BOOKING_FIELDS.updatedAt]: new Date(),
          });
        }
      }

      res.status(200).json({ ok: true });
    } catch (error) {
      logger.error("Stripe webhook processing failed", error);
      res.status(400).json({ error: "Webhook error" });
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
    const operatorId =
      after[BOOKING_FIELDS.operatorId] || after[BOOKING_FIELDS.legacyDriverId];
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

async function updateBookingPaymentState({ orderNumber, paymentStatus, transactionId, extra = {} }) {
  if (!orderNumber) {
    return;
  }

  const snapshot = await db
    .collection(COLLECTIONS.bookings)
    .where(BOOKING_FIELDS.orderNumber, "==", orderNumber)
    .limit(1)
    .get();

  if (snapshot.empty) {
    logger.warn("No booking found for payment state update", {
      orderNumber,
      paymentStatus,
    });
    return;
  }

  const updatePayload = {
    [BOOKING_FIELDS.paymentStatus]: paymentStatus,
    [BOOKING_FIELDS.updatedAt]: new Date(),
    ...extra,
  };

  if (transactionId) {
    updatePayload[BOOKING_FIELDS.transactionId] = transactionId;
  }

  await snapshot.docs[0].ref.update(updatePayload);
}

async function cancelOrRefundPaymentIntent({ stripe, paymentIntentId, orderNumber, reason }) {
  const intent = await stripe.paymentIntents.retrieve(paymentIntentId);

  // If already captured/succeeded, create a real refund so it appears in Stripe refunds.
  if (intent.status === "succeeded") {
    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
      reason: "requested_by_customer",
      metadata: {
        orderNumber,
        cancellationReason: reason || "requested_by_customer",
      },
    });

    await updateBookingPaymentState({
      orderNumber,
      paymentStatus: "refunded",
      transactionId: paymentIntentId,
      extra: {
        refundedAt: new Date(),
        refundId: refund.id,
      },
    });

    logger.info("Stripe payment refunded", {
      paymentIntentId,
      refundId: refund.id,
      orderNumber,
      refundStatus: refund.status,
    });

    return {
      status: "refunded",
      paymentIntentId,
      refundId: refund.id,
      refundStatus: refund.status,
    };
  }

  // For uncaptured/manual intents, canceling releases the authorization hold.
  if (
    intent.status === "requires_capture" ||
    intent.status === "requires_payment_method" ||
    intent.status === "requires_confirmation" ||
    intent.status === "requires_action" ||
    intent.status === "processing"
  ) {
    const cancelledIntent = await stripe.paymentIntents.cancel(paymentIntentId, {
      cancellation_reason: reason || "requested_by_customer",
    });

    await updateBookingPaymentState({
      orderNumber,
      paymentStatus: "cancelled",
      transactionId: cancelledIntent.id,
    });

    logger.info("Stripe payment intent cancelled", {
      paymentIntentId: cancelledIntent.id,
      orderNumber,
      reason: reason || "requested_by_customer",
      status: cancelledIntent.status,
    });

    return {
      status: "cancelled",
      paymentIntentId: cancelledIntent.id,
    };
  }

  if (intent.status === "canceled") {
    await updateBookingPaymentState({
      orderNumber,
      paymentStatus: "cancelled",
      transactionId: intent.id,
    });

    return {
      status: "cancelled",
      paymentIntentId: intent.id,
    };
  }

  throw new Error(`Unsupported PaymentIntent status for cancellation: ${intent.status}`);
}

exports.releasePaymentOnBookingRejected = onDocumentUpdated(
  {
    document: "bookings/{bookingId}",
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) {
      return;
    }

    const previousStatus = String(before[BOOKING_FIELDS.status] || "");
    const newStatus = String(after[BOOKING_FIELDS.status] || "");
    if (previousStatus === newStatus || newStatus !== "rejected") {
      return;
    }

    const paymentIntentId = String(after[BOOKING_FIELDS.transactionId] || "").trim();
    const orderNumber = String(after[BOOKING_FIELDS.orderNumber] || "").trim();

    if (!paymentIntentId || !orderNumber) {
      logger.warn("Skipping payment release/refund for rejected booking due to missing payment metadata", {
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
      });
      return;
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      logger.error("releasePaymentOnBookingRejected missing STRIPE_SECRET_KEY");
      return;
    }

    const stripe = new Stripe(secretKey);

    try {
      const result = await cancelOrRefundPaymentIntent({
        stripe,
        paymentIntentId,
        orderNumber,
        reason: "all_operators_rejected",
      });

      logger.info("Payment release/refund processed for rejected booking", {
        bookingId: event.params.bookingId,
        orderNumber,
        paymentIntentId,
        outcome: result.status,
      });
    } catch (error) {
      logger.error("Failed to release/refund payment for rejected booking", {
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
        message: error?.message || "Unknown Stripe error",
      });
    }
  }
);

exports.capturePaymentOnBookingCompleted = onDocumentUpdated(
  {
    document: "bookings/{bookingId}",
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) {
      return;
    }

    const previousStatus = String(before[BOOKING_FIELDS.status] || "");
    const newStatus = String(after[BOOKING_FIELDS.status] || "");
    if (previousStatus === newStatus || newStatus !== "completed") {
      return;
    }

    const paymentIntentId = String(after[BOOKING_FIELDS.transactionId] || "").trim();
    const orderNumber = String(after[BOOKING_FIELDS.orderNumber] || "").trim();

    if (!paymentIntentId || !orderNumber) {
      logger.warn("Skipping auto-capture for completed booking due to missing payment metadata", {
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
      });
      return;
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      logger.error("capturePaymentOnBookingCompleted missing STRIPE_SECRET_KEY");
      return;
    }

    const stripe = new Stripe(secretKey);

    try {
      const intent = await stripe.paymentIntents.retrieve(paymentIntentId);

      if (intent.status === "requires_capture") {
        const capturedIntent = await stripe.paymentIntents.capture(paymentIntentId);
        await updateBookingPaymentState({
          orderNumber,
          paymentStatus: "paid",
          transactionId: capturedIntent.id,
        });

        logger.info("Auto-captured payment for completed booking", {
          bookingId: event.params.bookingId,
          paymentIntentId: capturedIntent.id,
          orderNumber,
          status: capturedIntent.status,
        });
        return;
      }

      if (intent.status === "succeeded") {
        await updateBookingPaymentState({
          orderNumber,
          paymentStatus: "paid",
          transactionId: intent.id,
        });

        logger.info("Payment already captured for completed booking", {
          bookingId: event.params.bookingId,
          paymentIntentId: intent.id,
          orderNumber,
        });
        return;
      }

      logger.warn("Completed booking has non-capturable payment status", {
        bookingId: event.params.bookingId,
        paymentIntentId: intent.id,
        orderNumber,
        paymentIntentStatus: intent.status,
      });
    } catch (error) {
      logger.error("Auto-capture on booking completion failed", {
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
        message: error?.message || "Unknown Stripe error",
      });
    }
  }
);

exports.capturePaymentIntent = onCall(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const data = request.data || {};
    const paymentIntentId = String(data.paymentIntentId || "").trim();
    const orderNumber = String(data.orderNumber || "").trim();

    if (!paymentIntentId) {
      throw new HttpsError("invalid-argument", "paymentIntentId is required.");
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      throw new HttpsError("failed-precondition", "STRIPE_SECRET_KEY is not configured.");
    }

    const stripe = new Stripe(secretKey);

    try {
      const intent = await stripe.paymentIntents.capture(paymentIntentId);

      await updateBookingPaymentState({
        orderNumber,
        paymentStatus: "paid",
        transactionId: intent.id,
      });

      logger.info("Stripe payment intent captured", {
        paymentIntentId: intent.id,
        orderNumber,
        status: intent.status,
      });

      return {
        status: "captured",
        paymentIntentId: intent.id,
        amountCaptured: intent.amount_received,
      };
    } catch (error) {
      logger.error("Stripe payment intent capture failed", {
        paymentIntentId,
        message: error?.message || "Unknown Stripe error",
        orderNumber,
      });
      throw new HttpsError("internal", `Failed to capture payment: ${error?.message || "Unknown error"}`);
    }
  }
);

exports.cancelPaymentIntent = onCall(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const data = request.data || {};
    const paymentIntentId = String(data.paymentIntentId || "").trim();
    const orderNumber = String(data.orderNumber || "").trim();
    const reason = String(data.reason || "").trim();

    if (!paymentIntentId) {
      throw new HttpsError("invalid-argument", "paymentIntentId is required.");
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      throw new HttpsError("failed-precondition", "STRIPE_SECRET_KEY is not configured.");
    }

    const stripe = new Stripe(secretKey);

    try {
      return await cancelOrRefundPaymentIntent({
        stripe,
        paymentIntentId,
        orderNumber,
        reason,
      });
    } catch (error) {
      logger.error("Stripe payment intent cancellation failed", {
        paymentIntentId,
        message: error?.message || "Unknown Stripe error",
        orderNumber,
      });
      throw new HttpsError("internal", `Failed to cancel payment: ${error?.message || "Unknown error"}`);
    }
  }
);

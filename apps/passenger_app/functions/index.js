const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret, defineString } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldPath, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const Stripe = require("stripe");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const STRIPE_CURRENCY = defineString("STRIPE_CURRENCY");
const MIGRATION_ADMIN_UIDS = defineString("MIGRATION_ADMIN_UIDS");
const BOOKING_ARCHIVE_RETENTION_DAYS = defineString("BOOKING_ARCHIVE_RETENTION_DAYS");

const COLLECTIONS = {
  bookings: "bookings",
  bookingsArchive: "bookings_archive",
  orderNumberIndex: "order_number_index",
  fares: "fares",
  jetties: "jetties",
  operators: "operators",
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
  operatorUid: "operatorUid",
  operatorId: "operatorId",
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

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Validates payment intent creation parameters.
 * @param {Object} params - Payment parameters
 * @returns {Object} - Validation result { valid: boolean, error?: string }
 */
function validatePaymentIntentParams(params) {
  const { amount, currency, orderNumber, payerName, payerEmail, idempotencyKey } = params;

  if (!(amount > 0)) {
    return { valid: false, error: "amount must be greater than 0" };
  }
  if (!currency || typeof currency !== "string") {
    return { valid: false, error: "currency is required and must be a string" };
  }
  if (!orderNumber || typeof orderNumber !== "string") {
    return { valid: false, error: "orderNumber is required and must be a string" };
  }
  if (!payerName || typeof payerName !== "string") {
    return { valid: false, error: "payerName is required and must be a string" };
  }
  if (!payerEmail || typeof payerEmail !== "string") {
    return { valid: false, error: "payerEmail is required and must be a string" };
  }
  if (!idempotencyKey || typeof idempotencyKey !== "string") {
    return { valid: false, error: "idempotencyKey is required and must be a string" };
  }

  return { valid: true };
}

/**
 * Core payment intent creation logic shared by callable and HTTP functions.
 * @param {Stripe} stripe - Stripe client instance
 * @param {Object} params - Payment parameters (amount, currency, etc.)
 * @returns {Object} - Created payment intent
 */
async function createPaymentIntentCore(stripe, params) {
  const { amount, currency, orderNumber, payerName, payerEmail, payerTelephoneNumber, idempotencyKey, description, userId } = params;

  const amountInMinorUnit = Math.round(amount * 100);
  if (!(amountInMinorUnit > 0)) {
    throw new Error("Amount must be at least 0.01");
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
        userId,
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

  return intent;
}

/**
 * Ensures webhook event is processed only once using idempotency.
 * @param {string} eventId - Stripe event ID
 * @returns {boolean} - True if event is new; false if already processed
 */
async function isWebhookEventNew(eventId) {
  const ref = db.collection("webhook_events").doc(eventId);
  const doc = await ref.get();

  if (doc.exists) {
    logger.info("Skipping duplicate webhook event", { eventId });
    return false;
  }

  // Mark event as processed
  await ref.set({ processedAt: new Date() });
  return true;
}

/**
 * Handles refund for a succeeded/captured payment.
 */
async function handleSucceededRefund(stripe, intent, orderNumber, reason) {
  logger.debug("Creating Stripe refund for succeeded payment", { paymentIntentId: intent.id, orderNumber });
  
  const refund = await stripe.refunds.create({
    payment_intent: intent.id,
    reason: "requested_by_customer",
    metadata: {
      orderNumber,
      cancellationReason: reason || "requested_by_customer",
    },
  });

  logger.debug("Refund created", { refundId: refund.id, status: refund.status });

  await updateBookingPaymentState({
    orderNumber,
    paymentStatus: "refunded",
    transactionId: intent.id,
    extra: {
      refundedAt: new Date(),
      refundId: refund.id,
    },
  });

  logger.info("Stripe payment refunded", {
    paymentIntentId: intent.id,
    refundId: refund.id,
    orderNumber,
    refundStatus: refund.status,
  });

  return {
    status: "refunded",
    paymentIntentId: intent.id,
    refundId: refund.id,
    refundStatus: refund.status,
  };
}

/**
 * Handles cancellation of an uncaptured/authorized payment.
 */
async function handleUncapturedCancel(stripe, intent, orderNumber, reason) {
  const stripeCancellationReason = toStripeCancellationReason(reason);
  logger.debug("Cancelling uncaptured payment intent", { paymentIntentId: intent.id, status: intent.status });

  const cancelledIntent = await stripe.paymentIntents.cancel(intent.id, {
    cancellation_reason: stripeCancellationReason,
  });

  logger.debug("Payment intent cancelled", { paymentIntentId: cancelledIntent.id, status: cancelledIntent.status });

  await updateBookingPaymentState({
    orderNumber,
    paymentStatus: "cancelled",
    transactionId: cancelledIntent.id,
  });

  logger.info("Stripe payment intent cancelled", {
    paymentIntentId: cancelledIntent.id,
    orderNumber,
    reason: reason || "requested_by_customer",
    stripeCancellationReason,
    status: cancelledIntent.status,
  });

  return {
    status: "cancelled",
    paymentIntentId: cancelledIntent.id,
  };
}

/**
 * Creates a Stripe PaymentIntent via callable Firebase function.
 * Uses manual capture for e-hailing hold/release payment lifecycle.
 * Requires App Check validation.
 * 
 * Request data:
 *   - amount: number (in MYR or specified currency)
 *   - currency: string (defaults to STRIPE_CURRENCY environment variable)
 *   - orderNumber: string (booking order ID)
 *   - payerName: string
 *   - payerEmail: string
 *   - payerTelephoneNumber: string
 *   - idempotencyKey: string (stable key for retries with same parameters)
 * 
 * Returns: { status: "ready", paymentIntentId, clientSecret }
 */
exports.createStripePaymentIntent = onCall(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
    enforceAppCheck: true,
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

    // Validate input parameters
    const validation = validatePaymentIntentParams({
      amount,
      currency,
      orderNumber,
      payerName,
      payerEmail,
      idempotencyKey,
    });

    if (!validation.valid) {
      throw new HttpsError("invalid-argument", validation.error);
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      throw new HttpsError("failed-precondition", "STRIPE_SECRET_KEY is not configured.");
    }

    const stripe = new Stripe(secretKey);

    try {
      const intent = await createPaymentIntentCore(stripe, {
        amount,
        currency,
        orderNumber,
        payerName,
        payerEmail,
        payerTelephoneNumber,
        idempotencyKey,
        description,
        userId: request.auth.uid,
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
        stripeErrorCode: error?.code || "unknown",
      });
      throw new HttpsError("internal", "Unable to initialize Stripe payment.");
    }
  }
);

/**
 * Creates a Stripe PaymentIntent via HTTP endpoint.
 * Alternative to callable for clients without App Check support.
 * Verifies Firebase ID token from Authorization header.
 */
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

      // Validate input parameters
      const validation = validatePaymentIntentParams({
        amount,
        currency,
        orderNumber,
        payerName,
        payerEmail,
        idempotencyKey,
      });

      if (!validation.valid) {
        res.status(400).json({ status: "failed", message: validation.error });
        return;
      }

      const secretKey = STRIPE_SECRET_KEY.value();
      if (!secretKey || !secretKey.trim()) {
        res.status(500).json({ status: "failed", message: "STRIPE_SECRET_KEY is not configured." });
        return;
      }

      const stripe = new Stripe(secretKey);
      const intent = await createPaymentIntentCore(stripe, {
        amount,
        currency,
        orderNumber,
        payerName,
        payerEmail,
        payerTelephoneNumber,
        idempotencyKey,
        description,
        userId: decoded.uid,
      });

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

/**
 * Stripe webhook handler for payment intent events.
 * Validates webhook signature and updates booking payment status based on:
 * - payment_intent.succeeded: Payment fully captured
 * - payment_intent.amount.capturably_held: Payment authorized (hold placed)
 * 
 * Uses idempotency tracking to prevent duplicate event processing.
 * Stores all events in webhook_events collection for audit.
 */
exports.stripeWebhook = onRequest(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET],
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
    const webhookSecret = STRIPE_WEBHOOK_SECRET.value();
    if (!webhookSecret) {
      logger.error("stripeWebhook called without STRIPE_WEBHOOK_SECRET configured");
      res.status(500).json({ error: "Stripe webhook secret not configured" });
      return;
    }

    try {
      const signature = req.headers["stripe-signature"];
      const event = stripe.webhooks.constructEvent(req.rawBody, signature, webhookSecret);

      const eventId = String(event?.id || "unknown");
      const eventType = String(event?.type || "unknown");
      const payloadObject = event?.data?.object || {};
      const paymentIntentId = String(payloadObject.id || "");
      const status = String(payloadObject.status || "unknown");
      const orderNumber = String(payloadObject?.metadata?.orderNumber || "");

      // Check idempotency: skip if already processed
      if (!(await isWebhookEventNew(eventId))) {
        res.status(200).json({ ok: true });
        return;
      }

      await db.collection("payment_webhooks").add({
        provider: "stripe",
        eventId,
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

/**
 * Notifies online operators of incoming booking requests.
 * Triggered when a new booking is created with status "pending".
 * Gets list of online operators and sends FCM notifications to their devices.
 */
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

/**
 * Notifies passenger and operator when booking status changes.
 * Handles transitions: pending→accepted→on_the_way→completed/cancelled/rejected.
 * Sends localized status messages to both parties.
 * Cleans up invalid FCM tokens from responses.
 */
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
    const operatorUid = after[BOOKING_FIELDS.operatorUid] || after[BOOKING_FIELDS.operatorId];
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

    if (operatorUid) {
      const operatorToken = await getDeviceToken(
        COLLECTIONS.operatorDevices,
        operatorUid,
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

function isTerminalBookingStatus(status) {
  return status === "completed" || status === "cancelled" || status === "rejected";
}

async function cleanupOrderNumberReservation(orderNumber) {
  const normalizedOrderNumber = String(orderNumber || "").trim();
  if (!normalizedOrderNumber) {
    return false;
  }

  const indexRef = db.collection(COLLECTIONS.orderNumberIndex).doc(normalizedOrderNumber);
  const indexSnap = await indexRef.get();

  if (!indexSnap.exists) {
    return false;
  }

  await indexRef.delete();
  return true;
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

function toStripeCancellationReason(reason) {
  const normalized = String(reason || "").trim().toLowerCase();
  if (
    normalized === "duplicate" ||
    normalized === "fraudulent" ||
    normalized === "requested_by_customer" ||
    normalized === "abandoned"
  ) {
    return normalized;
  }
  return "requested_by_customer";
}

function toDateOrNull(value) {
  if (!value) {
    return null;
  }

  if (typeof value?.toDate === "function") {
    return value.toDate();
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizeJettyName(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function parseBoolean(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (normalized === "true" || normalized === "1") {
      return true;
    }
    if (normalized === "false" || normalized === "0") {
      return false;
    }
  }

  return fallback;
}

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (Number.isNaN(parsed)) {
    return fallback;
  }
  return parsed;
}

function parsePositiveRetentionDays(value, fallback = 180) {
  const parsed = parseInteger(value, fallback);
  if (parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function parseMigrationCollections(value) {
  if (!value) {
    return [COLLECTIONS.fares, COLLECTIONS.bookings];
  }

  const source = Array.isArray(value)
    ? value
    : String(value)
        .split(",")
        .map((item) => item.trim());

  const normalized = source
    .map((item) => String(item || "").trim().toLowerCase())
    .filter(Boolean);

  const allowed = new Set([COLLECTIONS.fares, COLLECTIONS.bookings]);
  const deduped = [...new Set(normalized)].filter((item) => allowed.has(item));
  return deduped.length > 0 ? deduped : [COLLECTIONS.fares, COLLECTIONS.bookings];
}

function parseAdminUidAllowlist() {
  return new Set(
    String(MIGRATION_ADMIN_UIDS.value() || "")
      .split(",")
      .map((uid) => uid.trim())
      .filter(Boolean)
  );
}

async function buildJettyNameMap() {
  const snapshot = await db.collection(COLLECTIONS.jetties).get();
  const map = new Map();

  for (const doc of snapshot.docs) {
    const name = normalizeJettyName(doc.data()?.name);
    if (!name) {
      continue;
    }

    if (!map.has(name)) {
      map.set(name, doc.id);
    }
  }

  return map;
}

function buildJettyIdPatch(docData, jettyNameMap) {
  const patch = {};
  const warnings = [];

  const originJettyId = String(docData.originJettyId || "").trim();
  const destinationJettyId = String(docData.destinationJettyId || "").trim();

  if (!originJettyId) {
    const originName = normalizeJettyName(docData.origin);
    const resolvedOriginId = originName ? jettyNameMap.get(originName) : null;
    if (resolvedOriginId) {
      patch.originJettyId = resolvedOriginId;
    } else {
      warnings.push("origin_unresolved");
    }
  }

  if (!destinationJettyId) {
    const destinationName = normalizeJettyName(docData.destination);
    const resolvedDestinationId = destinationName ? jettyNameMap.get(destinationName) : null;
    if (resolvedDestinationId) {
      patch.destinationJettyId = resolvedDestinationId;
    } else {
      warnings.push("destination_unresolved");
    }
  }

  return {
    patch,
    warnings,
  };
}

async function runJettyBackfillPage({
  collection,
  limit,
  startAfterDocId,
  dryRun,
  actorUid,
  jettyNameMap,
}) {
  let query = db
    .collection(collection)
    .orderBy(FieldPath.documentId())
    .limit(limit);

  if (startAfterDocId) {
    query = query.startAfter(startAfterDocId);
  }

  const snapshot = await query.get();
  const now = new Date();
  let updated = 0;
  let scanned = 0;
  let unresolved = 0;
  const unresolvedDocIds = [];
  const updateBatch = db.batch();

  for (const doc of snapshot.docs) {
    scanned += 1;
    const data = doc.data() || {};
    const { patch, warnings } = buildJettyIdPatch(data, jettyNameMap);

    if (warnings.length > 0) {
      unresolved += 1;
      unresolvedDocIds.push(doc.id);
    }

    if (Object.keys(patch).length === 0) {
      continue;
    }

    patch.updatedAt = now;
    patch.jettyBackfillAt = now;
    patch.jettyBackfillBy = actorUid;

    updated += 1;
    if (!dryRun) {
      updateBatch.update(doc.ref, patch);
    }
  }

  if (!dryRun && updated > 0) {
    await updateBatch.commit();
  }

  return {
    collection,
    scanned,
    updated,
    unresolved,
    unresolvedDocIds,
    nextCursor: snapshot.empty ? null : snapshot.docs[snapshot.docs.length - 1].id,
    done: snapshot.empty || snapshot.size < limit,
  };
}

async function runOperatorIsOnlineCleanupPage({
  limit,
  startAfterDocId,
  dryRun,
  actorUid,
}) {
  let query = db
    .collection(COLLECTIONS.operators)
    .orderBy(FieldPath.documentId())
    .limit(limit);

  if (startAfterDocId) {
    query = query.startAfter(startAfterDocId);
  }

  const snapshot = await query.get();
  const now = new Date();
  let scanned = 0;
  let updated = 0;
  const updateBatch = db.batch();

  for (const doc of snapshot.docs) {
    scanned += 1;
    const data = doc.data() || {};
    if (typeof data.isOnline === "undefined") {
      continue;
    }

    updated += 1;
    if (!dryRun) {
      updateBatch.update(doc.ref, {
        isOnline: FieldValue.delete(),
        updatedAt: now,
        onlineFieldCleanupAt: now,
        onlineFieldCleanupBy: actorUid,
      });
    }
  }

  if (!dryRun && updated > 0) {
    await updateBatch.commit();
  }

  return {
    collection: COLLECTIONS.operators,
    scanned,
    updated,
    nextCursor: snapshot.empty ? null : snapshot.docs[snapshot.docs.length - 1].id,
    done: snapshot.empty || snapshot.size < limit,
  };
}

/**
 * Backfills originJettyId/destinationJettyId on fares and bookings.
 *
 * Protection model:
 * - Firebase Auth bearer token required
 * - UID must be in MIGRATION_ADMIN_UIDS parameter
 *
 * Query/body options:
 * - dryRun: true|false (default true)
 * - limit: integer 1..500 (default 200)
 * - startAfter: doc id cursor for pagination
 * - collections: fares,bookings (CSV or array)
 */
exports.backfillJettyIds = onRequest(
  {
    region: "asia-southeast1",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({
        status: "failed",
        message: "Method not allowed",
      });
      return;
    }

    const authHeader = String(req.headers.authorization || "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({
        status: "failed",
        message: "Missing Firebase ID token",
      });
      return;
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(authHeader.substring("Bearer ".length).trim());
    } catch (error) {
      logger.warn("backfillJettyIds unauthorized token", {
        message: error?.message || "Unknown token verification error",
      });
      res.status(401).json({
        status: "failed",
        message: "Invalid Firebase ID token",
      });
      return;
    }

    const allowlist = parseAdminUidAllowlist();
    if (!allowlist.has(decodedToken.uid)) {
      logger.warn("backfillJettyIds forbidden for uid", {
        uid: decodedToken.uid,
      });
      res.status(403).json({
        status: "failed",
        message: "Forbidden",
      });
      return;
    }

    const payload = req.body || {};
    const dryRun = parseBoolean(payload.dryRun, true);
    const limitRaw = parseInteger(payload.limit, 200);
    const limit = Math.max(1, Math.min(500, limitRaw));
    const startAfter = String(payload.startAfter || "").trim();
    const collections = parseMigrationCollections(payload.collections);

    try {
      const jettyNameMap = await buildJettyNameMap();
      const results = [];

      for (const collection of collections) {
        const result = await runJettyBackfillPage({
          collection,
          limit,
          startAfterDocId: startAfter,
          dryRun,
          actorUid: decodedToken.uid,
          jettyNameMap,
        });
        results.push(result);
      }

      logger.info("backfillJettyIds completed", {
        actorUid: decodedToken.uid,
        dryRun,
        limit,
        startAfter,
        collections,
      });

      res.status(200).json({
        status: "ok",
        dryRun,
        limit,
        startAfter,
        collections,
        jettyNameMapSize: jettyNameMap.size,
        results,
      });
    } catch (error) {
      logger.error("backfillJettyIds failed", {
        actorUid: decodedToken.uid,
        message: error?.message || "Unknown migration failure",
      });
      res.status(500).json({
        status: "failed",
        message: "Backfill failed",
      });
    }
  }
);

/**
 * Removes legacy operators.isOnline field from stored operator profiles.
 *
 * Protection model:
 * - Firebase Auth bearer token required
 * - UID must be in MIGRATION_ADMIN_UIDS parameter
 *
 * Query/body options:
 * - dryRun: true|false (default true)
 * - limit: integer 1..500 (default 200)
 * - startAfter: doc id cursor for pagination
 */
exports.cleanupLegacyOperatorOnlineField = onRequest(
  {
    region: "asia-southeast1",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({
        status: "failed",
        message: "Method not allowed",
      });
      return;
    }

    const authHeader = String(req.headers.authorization || "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({
        status: "failed",
        message: "Missing Firebase ID token",
      });
      return;
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(authHeader.substring("Bearer ".length).trim());
    } catch (error) {
      logger.warn("cleanupLegacyOperatorOnlineField unauthorized token", {
        message: error?.message || "Unknown token verification error",
      });
      res.status(401).json({
        status: "failed",
        message: "Invalid Firebase ID token",
      });
      return;
    }

    const allowlist = parseAdminUidAllowlist();
    if (!allowlist.has(decodedToken.uid)) {
      logger.warn("cleanupLegacyOperatorOnlineField forbidden for uid", {
        uid: decodedToken.uid,
      });
      res.status(403).json({
        status: "failed",
        message: "Forbidden",
      });
      return;
    }

    const payload = req.body || {};
    const dryRun = parseBoolean(payload.dryRun, true);
    const limitRaw = parseInteger(payload.limit, 200);
    const limit = Math.max(1, Math.min(500, limitRaw));
    const startAfter = String(payload.startAfter || "").trim();

    try {
      const result = await runOperatorIsOnlineCleanupPage({
        limit,
        startAfterDocId: startAfter,
        dryRun,
        actorUid: decodedToken.uid,
      });

      logger.info("cleanupLegacyOperatorOnlineField completed", {
        actorUid: decodedToken.uid,
        dryRun,
        limit,
        startAfter,
      });

      res.status(200).json({
        status: "ok",
        dryRun,
        limit,
        startAfter,
        result,
      });
    } catch (error) {
      logger.error("cleanupLegacyOperatorOnlineField failed", {
        actorUid: decodedToken.uid,
        message: error?.message || "Unknown migration failure",
      });
      res.status(500).json({
        status: "failed",
        message: "Cleanup failed",
      });
    }
  }
);

/**
 * Releases order_number_index reservation when booking reaches terminal status.
 * Prevents stale index documents from accumulating after trip lifecycle ends.
 */
exports.cleanupOrderNumberIndexOnTerminalBooking = onDocumentUpdated(
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

    const previousStatus = String(before[BOOKING_FIELDS.status] || "").trim().toLowerCase();
    const newStatus = String(after[BOOKING_FIELDS.status] || "").trim().toLowerCase();

    if (previousStatus === newStatus || !isTerminalBookingStatus(newStatus)) {
      return;
    }

    const orderNumber = String(after[BOOKING_FIELDS.orderNumber] || "").trim();
    if (!orderNumber) {
      return;
    }

    try {
      const removed = await cleanupOrderNumberReservation(orderNumber);
      logger.info("Order number reservation cleanup processed", {
        bookingId: event.params.bookingId,
        orderNumber,
        removed,
        terminalStatus: newStatus,
      });
    } catch (error) {
      logger.error("Failed to cleanup order number reservation", {
        alertType: "ORDER_INDEX_CLEANUP_FAILED",
        bookingId: event.params.bookingId,
        orderNumber,
        terminalStatus: newStatus,
        message: error?.message || "Unknown cleanup error",
      });
    }
  }
);

async function captureOrMarkPaidPaymentIntent({ stripe, paymentIntentId, orderNumber }) {
  const intent = await stripe.paymentIntents.retrieve(paymentIntentId);

  if (intent.status === "requires_capture") {
    const capturedIntent = await stripe.paymentIntents.capture(paymentIntentId);
    await updateBookingPaymentState({
      orderNumber,
      paymentStatus: "paid",
      transactionId: capturedIntent.id,
    });

    return {
      status: "captured",
      paymentIntentId: capturedIntent.id,
      paymentIntentStatus: capturedIntent.status,
    };
  }

  if (intent.status === "succeeded") {
    await updateBookingPaymentState({
      orderNumber,
      paymentStatus: "paid",
      transactionId: intent.id,
    });

    return {
      status: "paid",
      paymentIntentId: intent.id,
      paymentIntentStatus: intent.status,
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
      paymentIntentStatus: intent.status,
    };
  }

  throw new Error(`Unsupported PaymentIntent status for capture: ${intent.status}`);
}

async function cancelOrRefundPaymentIntent({ stripe, paymentIntentId, orderNumber, reason }) {
  let intent;
  try {
    logger.debug("Retrieving Stripe payment intent", { paymentIntentId, orderNumber });
    intent = await stripe.paymentIntents.retrieve(paymentIntentId);
    logger.debug("Payment intent retrieved successfully", { paymentIntentId, status: intent.status });
  } catch (retrieveError) {
    const errorMsg = String(retrieveError?.message || retrieveError || "Unknown error");
    logger.error("Failed to retrieve payment intent from Stripe", {
      paymentIntentId,
      orderNumber,
      error: errorMsg,
      errorCode: retrieveError?.code || "unknown",
    });
    throw retrieveError;
  }

  // Already captured/succeeded: create a real refund
  if (intent.status === "succeeded") {
    try {
      return await handleSucceededRefund(stripe, intent, orderNumber, reason);
    } catch (refundError) {
      const errorMsg = String(refundError?.message || refundError || "Unknown error");
      logger.error("Failed to create refund", { 
        paymentIntentId, 
        orderNumber, 
        error: errorMsg,
        errorCode: refundError?.code || "unknown",
      });
      throw refundError;
    }
  }

  // Uncaptured/authorized payment: cancel and release hold
  if (
    intent.status === "requires_capture" ||
    intent.status === "requires_payment_method" ||
    intent.status === "requires_confirmation" ||
    intent.status === "requires_action" ||
    intent.status === "processing"
  ) {
    try {
      return await handleUncapturedCancel(stripe, intent, orderNumber, reason);
    } catch (cancelError) {
      const errorMsg = String(cancelError?.message || cancelError || "Unknown error");
      logger.error("Failed to cancel payment intent", { 
        paymentIntentId, 
        orderNumber, 
        error: errorMsg,
        errorCode: cancelError?.code || "unknown",
      });
      throw cancelError;
    }
  }

  // Already cancelled
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

/**
 * Releases/refunds payment when a booking is rejected by all operators.
 * Cancels the PaymentIntent to release the authorization hold.
 * Updates booking payment_status to "cancelled".
 */
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
        alertType: "PAYMENT_RELEASE_FAILED",
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
        message: error?.message || "Unknown Stripe error",
      });
    }
  }
);

/**
 * Auto-captures payment when booking transitions to "completed".
 * Handles manual capture workflow: earlier hold → now capture.
 * Updates payment_status to "paid" upon successful capture.
 * 
 * Note: This is the companion to manual capture PaymentIntent creation.
 * For e-hailing workflow: ride → capture → money to operator/platform.
 */
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
      const result = await captureOrMarkPaidPaymentIntent({
        stripe,
        paymentIntentId,
        orderNumber,
      });

      logger.info("Payment reconciliation for completed booking succeeded", {
        bookingId: event.params.bookingId,
        paymentIntentId: result.paymentIntentId,
        orderNumber,
        outcome: result.status,
        paymentIntentStatus: result.paymentIntentStatus,
      });
    } catch (error) {
      logger.error("Auto-capture on booking completion failed", {
        alertType: "PAYMENT_CAPTURE_FAILED",
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
        message: error?.message || "Unknown Stripe error",
      });
    }
  }
);

/**
 * Manually captures a PaymentIntent via callable function.
 * Used for explicit capture control if auto-capture fails or is delayed.
 * Only works on intents in "requires_capture" status.
 */
exports.capturePaymentIntent = onCall(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
    enforceAppCheck: true,
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
      const result = await captureOrMarkPaidPaymentIntent({
        stripe,
        paymentIntentId,
        orderNumber,
      });

      logger.info("Stripe payment intent captured", {
        paymentIntentId: result.paymentIntentId,
        orderNumber,
        status: result.paymentIntentStatus,
        outcome: result.status,
      });

      return {
        status: "captured",
        paymentIntentId: result.paymentIntentId,
      };
    } catch (error) {
      logger.error("Stripe payment intent capture failed", {
        alertType: "PAYMENT_CAPTURE_FAILED",
        paymentIntentId,
        message: error?.message || "Unknown Stripe error",
        orderNumber,
      });
      throw new HttpsError("internal", `Failed to capture payment: ${error?.message || "Unknown error"}`);
    }
  }
);

/**
 * Manually cancels/refunds a PaymentIntent via callable function.
 * Handles both captured (true refund) and uncaptured (authorization release) intents.
 * 
 * For uncaptured: Cancels to release hold.
 * For captured: Creates a Refund object in Stripe.
 */
exports.cancelPaymentIntent = onCall(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
    enforceAppCheck: true,
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

/**
 * Releases/refunds payment when a booking is cancelled by passenger.
 * Cancels the PaymentIntent to release the authorization hold.
 * Updates booking payment_status to "cancelled".
 * 
 * Logs detailed error context with alert type "PAYMENT_RELEASE_FAILED" for alerting.
 */
exports.releasePaymentOnBookingCancelled = onDocumentUpdated(
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
    if (previousStatus === newStatus || newStatus !== "cancelled") {
      return;
    }

    const paymentIntentId = String(after[BOOKING_FIELDS.transactionId] || "").trim();
    const orderNumber = String(after[BOOKING_FIELDS.orderNumber] || "").trim();

    if (!paymentIntentId || !orderNumber) {
      logger.warn("Skipping payment release/refund for cancelled booking due to missing payment metadata", {
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
      });
      return;
    }

    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      logger.error("releasePaymentOnBookingCancelled missing STRIPE_SECRET_KEY");
      return;
    }

    const stripe = new Stripe(secretKey);

    try {
      logger.debug("Starting payment release/refund for cancelled booking", {
        bookingId: event.params.bookingId,
        orderNumber,
        paymentIntentId,
      });

      const result = await cancelOrRefundPaymentIntent({
        stripe,
        paymentIntentId,
        orderNumber,
        reason: "passenger_cancelled_booking",
      });

      logger.info("Payment release/refund processed for cancelled booking", {
        bookingId: event.params.bookingId,
        orderNumber,
        paymentIntentId,
        outcome: result.status,
      });
    } catch (error) {
      const errorMessage = String(error?.message || error || "Unknown error");
      const errorCode = String(error?.code || error?.type || "UNKNOWN");
      logger.error("Failed to release/refund payment for cancelled booking", {
        alertType: "PAYMENT_RELEASE_FAILED",
        bookingId: event.params.bookingId,
        paymentIntentId,
        orderNumber,
        errorCode,
        errorMessage,
      });
    }
  }
);

/**
 * Scheduled reconciliation of stale authorized payments (every 30 minutes).
 * Handles edge cases where automatic triggers may have failed:
 * - Captures completed bookings with "authorized" payment
 * - Releases cancelled/rejected bookings with "authorized" payment
 * 
 * Runs only on bookings with updatedAt <= 30 minutes ago.
 * Logs summary stats for monitoring.
 */
exports.reconcileStaleAuthorizedPayments = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Kuala_Lumpur",
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET_KEY],
  },
  async () => {
    const secretKey = STRIPE_SECRET_KEY.value();
    if (!secretKey || !secretKey.trim()) {
      logger.error("reconcileStaleAuthorizedPayments missing STRIPE_SECRET_KEY", {
        alertType: "PAYMENT_RECONCILE_FAILED",
      });
      return;
    }

    const stripe = new Stripe(secretKey);
    const staleCutoffMs = Date.now() - 30 * 60 * 1000;

    const snapshot = await db
      .collection(COLLECTIONS.bookings)
      .where(BOOKING_FIELDS.paymentStatus, "==", "authorized")
      .limit(200)
      .get();

    let released = 0;
    let captured = 0;
    let skipped = 0;
    let failed = 0;

    for (const doc of snapshot.docs) {
      const booking = doc.data() || {};
      const bookingId = doc.id;
      const status = String(booking[BOOKING_FIELDS.status] || "").trim().toLowerCase();
      const paymentIntentId = String(booking[BOOKING_FIELDS.transactionId] || "").trim();
      const orderNumber = String(booking[BOOKING_FIELDS.orderNumber] || "").trim();
      const updatedAt = toDateOrNull(booking[BOOKING_FIELDS.updatedAt]);
      const isStale = updatedAt ? updatedAt.getTime() <= staleCutoffMs : true;

      if (!paymentIntentId || !orderNumber || !isStale) {
        skipped += 1;
        continue;
      }

      try {
        if (status === "cancelled" || status === "rejected") {
          await cancelOrRefundPaymentIntent({
            stripe,
            paymentIntentId,
            orderNumber,
            reason: "requested_by_customer",
          });
          released += 1;
          continue;
        }

        if (status === "completed") {
          await captureOrMarkPaidPaymentIntent({
            stripe,
            paymentIntentId,
            orderNumber,
          });
          captured += 1;
          continue;
        }

        skipped += 1;
      } catch (error) {
        failed += 1;
        logger.error("Payment reconciliation failed for booking", {
          alertType: "PAYMENT_RECONCILE_FAILED",
          bookingId,
          orderNumber,
          paymentIntentId,
          status,
          message: error?.message || "Unknown Stripe error",
        });
      }
    }

    logger.info("Payment reconciliation run completed", {
      scanned: snapshot.size,
      released,
      captured,
      skipped,
      failed,
    });
  }
);

/**
 * Scheduled cleanup for bookings_archive retention.
 *
 * Retention is configured by BOOKING_ARCHIVE_RETENTION_DAYS (default 180).
 * Deletes archive docs where archivedAt is older than retention cutoff.
 */
exports.cleanupExpiredBookingArchive = onSchedule(
  {
    schedule: "every day 02:00",
    timeZone: "Asia/Kuala_Lumpur",
    region: "asia-southeast1",
  },
  async () => {
    const retentionDays = parsePositiveRetentionDays(
      BOOKING_ARCHIVE_RETENTION_DAYS.value(),
      180
    );
    const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);

    const snapshot = await db
      .collection(COLLECTIONS.bookingsArchive)
      .where("archivedAt", "<", cutoff)
      .limit(300)
      .get();

    if (snapshot.empty) {
      logger.info("Archive retention cleanup completed", {
        retentionDays,
        cutoff: cutoff.toISOString(),
        scanned: 0,
        deleted: 0,
      });
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    logger.info("Archive retention cleanup completed", {
      retentionDays,
      cutoff: cutoff.toISOString(),
      scanned: snapshot.size,
      deleted: snapshot.size,
      hasMoreEligibleDocs: snapshot.size >= 300,
    });
  }
);

/**
 * Scheduled cleanup for stale order_number_index reservations.
 *
 * Removes reservation docs where expiresAt is in the past. This protects
 * against abandoned payment flows leaving orphaned order reservations.
 */
exports.cleanupExpiredOrderNumberReservations = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Kuala_Lumpur",
    region: "asia-southeast1",
  },
  async () => {
    const now = new Date();
    const snapshot = await db
      .collection(COLLECTIONS.orderNumberIndex)
      .where("expiresAt", "<", now)
      .limit(300)
      .get();

    if (snapshot.empty) {
      logger.info("Order reservation cleanup completed", {
        scanned: 0,
        deleted: 0,
      });
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    logger.info("Order reservation cleanup completed", {
      scanned: snapshot.size,
      deleted: snapshot.size,
      hasMoreEligibleDocs: snapshot.size >= 300,
    });
  }
);

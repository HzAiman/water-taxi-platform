const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
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
  driverId: "driverId",
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

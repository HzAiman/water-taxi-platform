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
const MINIMUM_STRIPE_CHARGE_BY_CURRENCY = {
  myr: 2.00,
};

const COLLECTIONS = {
  bookings: "bookings",
  bookingsArchive: "bookings_archive",
  polylines: "polylines",
  orderNumberIndex: "order_number_index",
  fares: "fares",
  jetties: "jetties",
  operators: "operators",
  operatorIdIndex: "operator_id_index",
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
  originJettyId: "originJettyId",
  destinationJettyId: "destinationJettyId",
  originCoords: "originCoords",
  destinationCoords: "destinationCoords",
  operatorUid: "operatorUid",
  operatorId: "operatorId",
  assignedOperatorName: "assignedOperatorName",
  assignedOperatorDisplayId: "assignedOperatorDisplayId",
  assignedOperatorPhone: "assignedOperatorPhone",
  operatorLat: "operatorLat",
  operatorLng: "operatorLng",
  updatedAt: "updatedAt",
  adultCount: "adultCount",
  childCount: "childCount",
  passengerCount: "passengerCount",
  paymentStatus: "paymentStatus",
  orderNumber: "orderNumber",
  transactionId: "transactionId",
  rejectedBy: "rejectedBy",
  createdAt: "createdAt",
  pooled: "pooled",
  poolGroupId: "poolGroupId",
  poolSequence: "poolSequence",
  poolCriteriaVersion: "poolCriteriaVersion",
  poolMax: "poolMax",
  poolEligibilityScore: "poolEligibilityScore",
  poolEtaSnapshot: "poolEtaSnapshot",
  routePolylineId: "routePolylineId",
  routePolyline: "routePolyline",
  routeDirection: "routeDirection",
  poolStatus: "poolStatus",
  poolStopPlan: "poolStopPlan",
  currentStopIndex: "currentStopIndex",
  currentStopId: "currentStopId",
  currentPoolStopId: "currentPoolStopId",
  poolPickupStopId: "poolPickupStopId",
  poolDropoffStopId: "poolDropoffStopId",
  poolPhase: "poolPhase",
  pickedUpAt: "pickedUpAt",
  droppedOffAt: "droppedOffAt",
  passengerPickedUpAt: "passengerPickedUpAt",
  onboard: "onboard",
  poolDeferredForOperatorUid: "poolDeferredForOperatorUid",
  poolDeferredRouteDirection: "poolDeferredRouteDirection",
  poolDeferredPoolGroupId: "poolDeferredPoolGroupId",
  poolDeferredReason: "poolDeferredReason",
  poolDeferredUntil: "poolDeferredUntil",
  poolDeferredAt: "poolDeferredAt",
};

const BOOKING_SUBCOLLECTIONS = {
  statusHistory: "statusHistory",
};

const STATUS_HISTORY_FIELDS = {
  from: "from",
  to: "to",
  changedBy: "changedBy",
  source: "source",
  timestamp: "timestamp",
};

const POOLING_POLICY = {
  maxConcurrent: 3,
  pickupWindowMinutes: 15,
  addedEtaLimitMinutes: 8,
  staleAcceptedMinutes: 12,
  criteriaVersion: "v2_distance_deviation_eta",
  maxPickupDistanceMeters: 1000,
  maxRouteDeviationMeters: 1200,
  maxRouteOvershootRatio: 1.05,
  speedMetersPerSecond: 5.5,
  nextSweepDeferMinutes: 20,
  stopArrivalRadiusMeters: 30,
};

const PENDING_NO_OPERATOR_POLICY = {
  timeoutMinutes: 5,
  batchLimit: 100,
  changedBy: "system:no_online_operators",
  source: "rejectStalePendingBookingsWithoutOnlineOperators",
};

const DEVICE_FIELDS = {
  token: "token",
  appRole: "appRole",
};

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isWithinMinutes(then, now, windowMinutes) {
  if (!then || !now) return false;
  const diffMs = Math.abs(now.getTime() - then.getTime());
  return diffMs <= windowMinutes * 60 * 1000;
}

function asString(value) {
  return value == null ? "" : String(value).trim();
}

function asNonNegativeInt(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

const EARTH_RADIUS_METERS = 6371000;

function asGeoPoint(value) {
  if (!value) return null;
  if (
    typeof value.latitude === "number" &&
    typeof value.longitude === "number"
  ) {
    return { lat: value.latitude, lng: value.longitude };
  }
  if (
    typeof value._latitude === "number" &&
    typeof value._longitude === "number"
  ) {
    return { lat: value._latitude, lng: value._longitude };
  }
  return null;
}

function toRadians(deg) {
  return (deg * Math.PI) / 180;
}

function haversineDistanceMeters(a, b) {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const lat1 = toRadians(a.lat);
  const lat2 = toRadians(b.lat);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const aa = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLng * sinLng;
  const c = 2 * Math.atan2(Math.sqrt(aa), Math.sqrt(1 - aa));
  return EARTH_RADIUS_METERS * c;
}

function toXY(point, refLat) {
  const latRad = toRadians(point.lat);
  const lngRad = toRadians(point.lng);
  const refLatRad = toRadians(refLat);
  return {
    x: EARTH_RADIUS_METERS * lngRad * Math.cos(refLatRad),
    y: EARTH_RADIUS_METERS * latRad,
  };
}

function lineMetricsMeters(origin, destination, point) {
  const refLat = (origin.lat + destination.lat + point.lat) / 3;
  const a = toXY(origin, refLat);
  const b = toXY(destination, refLat);
  const p = toXY(point, refLat);
  const abx = b.x - a.x;
  const aby = b.y - a.y;
  const abLen2 = abx * abx + aby * aby;
  if (abLen2 <= 1) {
    return {
      deviationMeters: haversineDistanceMeters(origin, point),
      alongTrackRatio: 0,
    };
  }

  const apx = p.x - a.x;
  const apy = p.y - a.y;
  const t = (apx * abx + apy * aby) / abLen2;
  const projX = a.x + t * abx;
  const projY = a.y + t * aby;
  const dx = p.x - projX;
  const dy = p.y - projY;
  const deviation = Math.sqrt(dx * dx + dy * dy);
  return { deviationMeters: deviation, alongTrackRatio: t };
}

function normalizeRoutePoint(entry) {
  const geo = asGeoPoint(entry);
  if (isValidPoint(geo)) return geo;
  if (entry && typeof entry === "object") {
    const lat = Number(entry.lat ?? entry.latitude ?? entry._latitude);
    const lng = Number(
      entry.lng ?? entry.longitude ?? entry.lon ?? entry._longitude
    );
    const point = { lat, lng };
    return isValidPoint(point) ? point : null;
  }
  return null;
}

function unwrapRoutePolylinePayload(raw) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    return (
      raw.path ||
      raw.coordinates ||
      raw.polyline ||
      raw.points ||
      raw.geometry ||
      raw[BOOKING_FIELDS.routePolyline]
    );
  }
  return raw;
}

function routePointsFromRaw(raw) {
  const unwrapped = unwrapRoutePolylinePayload(raw);
  if (!Array.isArray(unwrapped)) return [];
  return unwrapped
    .map(normalizeRoutePoint)
    .filter((point) => isValidPoint(point));
}

function routePointsFromBooking(booking) {
  return routePointsFromRaw(booking?.[BOOKING_FIELDS.routePolyline]);
}

function isValidPoint(point) {
  return (
    point &&
    Number.isFinite(point.lat) &&
    Number.isFinite(point.lng) &&
    point.lat >= -90 &&
    point.lat <= 90 &&
    point.lng >= -180 &&
    point.lng <= 180 &&
    !(point.lat === 0 && point.lng === 0)
  );
}

function getBookingPoint(booking, field) {
  return asGeoPoint(booking?.[field]);
}

function getOperatorPoint(booking) {
  const lat = Number(booking?.[BOOKING_FIELDS.operatorLat]);
  const lng = Number(booking?.[BOOKING_FIELDS.operatorLng]);
  const point = { lat, lng };
  return isValidPoint(point) ? point : null;
}

function pointFromPoolStop(stop) {
  const point = {
    lat: Number(stop?.lat),
    lng: Number(stop?.lng),
  };
  return isValidPoint(point) ? point : null;
}

function currentStopPointFromBooking(booking) {
  const stopPlan = Array.isArray(booking?.[BOOKING_FIELDS.poolStopPlan])
    ? booking[BOOKING_FIELDS.poolStopPlan]
    : [];
  if (stopPlan.length === 0) return null;

  const currentStopId = asString(
    booking?.[BOOKING_FIELDS.currentPoolStopId] ||
      booking?.[BOOKING_FIELDS.currentStopId]
  );
  if (currentStopId) {
    const byId = stopPlan.find((stop) => asString(stop?.stopId) === currentStopId);
    const point = pointFromPoolStop(byId);
    if (point) return point;
  }

  const currentStopIndex = Number(booking?.[BOOKING_FIELDS.currentStopIndex]);
  if (
    Number.isInteger(currentStopIndex) &&
    currentStopIndex >= 0 &&
    currentStopIndex < stopPlan.length
  ) {
    const point = pointFromPoolStop(stopPlan[currentStopIndex]);
    if (point) return point;
  }

  const firstIncomplete = stopPlan.find((stop) => {
    const status = asString(stop?.status);
    return status !== "completed" && status !== "skipped";
  });
  return pointFromPoolStop(firstIncomplete);
}

function selectEligibilityAnchorPoint(activeBookings, operatorPoint) {
  const hasActiveTrip = activeBookings.some(
    (booking) => asString(booking?.[BOOKING_FIELDS.status]) === "on_the_way"
  );

  if (hasActiveTrip) {
    if (isValidPoint(operatorPoint)) {
      return { point: operatorPoint, source: "request_operator" };
    }

    const storedOperatorPoint = activeBookings
      .map((booking) => getOperatorPoint(booking))
      .find((point) => isValidPoint(point));
    if (storedOperatorPoint) {
      return { point: storedOperatorPoint, source: "stored_operator" };
    }
  }

  const currentStopPoint = activeBookings
    .map((booking) => currentStopPointFromBooking(booking))
    .find((point) => isValidPoint(point));
  if (currentStopPoint) {
    return { point: currentStopPoint, source: "current_stop" };
  }

  const firstOrigin = activeBookings
    .map((booking) => getBookingEndpoints(booking)?.origin)
    .find((point) => isValidPoint(point));
  if (firstOrigin) {
    return { point: firstOrigin, source: "active_origin" };
  }

  return { point: null, source: "" };
}

function getBookingEndpoints(booking) {
  const origin = getBookingPoint(booking, BOOKING_FIELDS.originCoords);
  const destination = getBookingPoint(booking, BOOKING_FIELDS.destinationCoords);
  if (!isValidPoint(origin) || !isValidPoint(destination)) {
    return null;
  }
  return { origin, destination };
}

function isPassengerAlreadyPickedUp(booking) {
  return Boolean(
    booking?.[BOOKING_FIELDS.passengerPickedUpAt] ||
      booking?.[BOOKING_FIELDS.pickedUpAt] ||
      booking?.[BOOKING_FIELDS.onboard]
  );
}

function corridorLengthMeters(corridor) {
  return corridor.totalMeters || haversineDistanceMeters(
    corridor.origin,
    corridor.destination
  );
}

function buildCorridorFromBooking(booking) {
  const endpoints = getBookingEndpoints(booking);
  if (!endpoints) return null;

  const routePoints = routePointsFromBooking(booking);
  const points = routePoints.length >= 2
    ? routePoints
    : [endpoints.origin, endpoints.destination];
  const cumulativeMeters = [0];
  let totalMeters = 0;
  for (let i = 1; i < points.length; i += 1) {
    totalMeters += haversineDistanceMeters(points[i - 1], points[i]);
    cumulativeMeters.push(totalMeters);
  }

  return {
    origin: points[0],
    destination: points[points.length - 1],
    points,
    cumulativeMeters,
    totalMeters,
  };
}

function isClosedLoopRoute(points) {
  if (!Array.isArray(points) || points.length < 3) return false;
  return haversineDistanceMeters(points[0], points[points.length - 1]) <= 25;
}

function projectPointToRouteSegment(points, point) {
  let best = null;
  for (let i = 0; i < points.length - 1; i += 1) {
    const aPoint = points[i];
    const bPoint = points[i + 1];
    const refLat = (aPoint.lat + bPoint.lat + point.lat) / 3;
    const a = toXY(aPoint, refLat);
    const b = toXY(bPoint, refLat);
    const p = toXY(point, refLat);
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const abLen2 = abx * abx + aby * aby;
    const rawT =
      abLen2 <= 1 ? 0 : ((p.x - a.x) * abx + (p.y - a.y) * aby) / abLen2;
    const t = Math.max(0, Math.min(1, rawT));
    const projectedPoint = {
      lat: aPoint.lat + (bPoint.lat - aPoint.lat) * t,
      lng: aPoint.lng + (bPoint.lng - aPoint.lng) * t,
    };
    const deviationMeters = haversineDistanceMeters(projectedPoint, point);
    if (!best || deviationMeters < best.deviationMeters) {
      best = {
        point: projectedPoint,
        segmentIndex: i,
        deviationMeters,
      };
    }
  }
  return best;
}

function addDistinctRoutePoint(points, next) {
  if (!isValidPoint(next)) return;
  const last = points[points.length - 1];
  if (last && haversineDistanceMeters(last, next) <= 0.5) return;
  points.push(next);
}

function extractRouteSegment(points, start, end, routeDirection = "") {
  if (!Array.isArray(points) || points.length < 2 || !start || !end) {
    return [];
  }

  const normalizedDirection = normalizeRouteDirection(routeDirection);
  const segment = [start.point];
  const closedLoop = isClosedLoopRoute(points);

  if (closedLoop) {
    const segmentCount = points.length - 1;
    const step = normalizedDirection === "reverse" ? -1 : 1;
    let index = start.segmentIndex;
    let guard = 0;
    while (index !== end.segmentIndex && guard <= segmentCount + 1) {
      if (step > 0) {
        const nextIndex = (index + 1) % segmentCount;
        addDistinctRoutePoint(segment, points[nextIndex]);
        index = nextIndex;
      } else {
        addDistinctRoutePoint(segment, points[index]);
        index = (index - 1 + segmentCount) % segmentCount;
      }
      guard += 1;
    }
    addDistinctRoutePoint(segment, end.point);
    return segment;
  }

  if (start.segmentIndex <= end.segmentIndex) {
    for (let i = start.segmentIndex + 1; i <= end.segmentIndex; i += 1) {
      addDistinctRoutePoint(segment, points[i]);
    }
  } else {
    for (let i = start.segmentIndex; i >= end.segmentIndex + 1; i -= 1) {
      addDistinctRoutePoint(segment, points[i]);
    }
  }
  addDistinctRoutePoint(segment, end.point);
  return segment;
}

function routeSegmentForBooking(booking, routePoints) {
  const endpoints = getBookingEndpoints(booking);
  if (!endpoints || !Array.isArray(routePoints) || routePoints.length < 2) {
    return [];
  }

  const start = projectPointToRouteSegment(routePoints, endpoints.origin);
  const end = projectPointToRouteSegment(routePoints, endpoints.destination);
  return extractRouteSegment(
    routePoints,
    start,
    end,
    booking?.[BOOKING_FIELDS.routeDirection]
  );
}

async function hydrateBookingRouteGeometry(tx, booking) {
  const embedded = routePointsFromBooking(booking);
  if (embedded.length >= 2) return booking;

  const routePolylineId = asString(booking?.[BOOKING_FIELDS.routePolylineId]);
  if (!routePolylineId) return booking;

  const snap = await tx.get(
    db.collection(COLLECTIONS.polylines).doc(routePolylineId)
  );
  if (!snap.exists) return booking;

  const data = snap.data() || {};
  const sourcePoints = routePointsFromRaw(
    data.path ||
      data.coordinates ||
      data.polyline ||
      data.geometry ||
      data[BOOKING_FIELDS.routePolyline]
  );
  const segment = routeSegmentForBooking(booking, sourcePoints);
  if (segment.length < 2) return booking;

  return {
    ...booking,
    [BOOKING_FIELDS.routePolyline]: segment.map((point) => ({
      lat: point.lat,
      lng: point.lng,
    })),
    [BOOKING_FIELDS.routeDirection]:
      normalizeRouteDirection(booking?.[BOOKING_FIELDS.routeDirection]) ||
      "forward",
  };
}

async function hydrateBookingsRouteGeometry(tx, bookings) {
  return Promise.all(
    bookings.map((booking) => hydrateBookingRouteGeometry(tx, booking))
  );
}

function projectPointToCorridor(corridor, point) {
  if (!corridor?.points || corridor.points.length < 2) {
    const fallback = lineMetricsMeters(corridor.origin, corridor.destination, point);
    return {
      deviationMeters: fallback.deviationMeters,
      alongTrackRatio: fallback.alongTrackRatio,
      alongMeters: fallback.alongTrackRatio * corridorLengthMeters(corridor),
    };
  }

  let best = null;
  for (let i = 0; i < corridor.points.length - 1; i += 1) {
    const aPoint = corridor.points[i];
    const bPoint = corridor.points[i + 1];
    const refLat = (aPoint.lat + bPoint.lat + point.lat) / 3;
    const a = toXY(aPoint, refLat);
    const b = toXY(bPoint, refLat);
    const p = toXY(point, refLat);
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const abLen2 = abx * abx + aby * aby;
    const rawT = abLen2 <= 1 ? 0 : ((p.x - a.x) * abx + (p.y - a.y) * aby) / abLen2;
    const t = Math.max(0, Math.min(1, rawT));
    const projected = {
      x: a.x + t * abx,
      y: a.y + t * aby,
    };
    const dx = p.x - projected.x;
    const dy = p.y - projected.y;
    const deviationMeters = Math.sqrt(dx * dx + dy * dy);
    const segmentMeters = haversineDistanceMeters(aPoint, bPoint);
    const alongMeters = corridor.cumulativeMeters[i] + segmentMeters * t;
    if (!best || deviationMeters < best.deviationMeters) {
      best = { deviationMeters, alongMeters };
    }
  }

  const total = Math.max(corridor.totalMeters || 0, 1);
  return {
    deviationMeters: best.deviationMeters,
    alongMeters: best.alongMeters,
    alongTrackRatio: best.alongMeters / total,
  };
}

function routeMetricsForBooking(corridor, booking) {
  const endpoints = getBookingEndpoints(booking);
  if (!endpoints) return null;

  const originMetrics = projectPointToCorridor(corridor, endpoints.origin);
  const destinationMetrics = projectPointToCorridor(
    corridor,
    endpoints.destination
  );
  const length = corridorLengthMeters(corridor);
  const originAlongMeters = originMetrics.alongMeters;
  const destinationAlongMeters = destinationMetrics.alongMeters;
  const pickupDistanceMeters = haversineDistanceMeters(
    corridor.origin,
    endpoints.origin
  );

  return {
    endpoints,
    originDeviationMeters: originMetrics.deviationMeters,
    destinationDeviationMeters: destinationMetrics.deviationMeters,
    originAlongTrackRatio: originMetrics.alongTrackRatio,
    destinationAlongTrackRatio: destinationMetrics.alongTrackRatio,
    originAlongMeters,
    destinationAlongMeters,
    pickupDistanceMeters,
  };
}

function isBookingDirectionCompatible(metrics) {
  if (!metrics) return false;
  return (
    metrics.destinationAlongTrackRatio + 0.02 >=
    metrics.originAlongTrackRatio
  );
}

function normalizeRouteDirection(value) {
  const normalized = asString(value).toLowerCase();
  return normalized === "forward" || normalized === "reverse"
    ? normalized
    : "";
}

function routeDirectionForMetrics(metrics) {
  if (!metrics) return "";
  return metrics.destinationAlongMeters >= metrics.originAlongMeters
    ? "forward"
    : "reverse";
}

function isBookingDirectionValidForPool(metrics, routeDirection) {
  if (!metrics) return false;
  const direction = normalizeRouteDirection(routeDirection);
  if (direction === "reverse") {
    return metrics.destinationAlongMeters < metrics.originAlongMeters;
  }
  return metrics.destinationAlongMeters > metrics.originAlongMeters;
}

function isBookingWithinCorridor(metrics) {
  if (!metrics) return false;
  const maxDeviation = Math.max(
    metrics.originDeviationMeters,
    metrics.destinationDeviationMeters
  );
  const maxAlong = Math.max(
    metrics.originAlongTrackRatio,
    metrics.destinationAlongTrackRatio
  );
  const minAlong = Math.min(
    metrics.originAlongTrackRatio,
    metrics.destinationAlongTrackRatio
  );

  return (
    maxDeviation <= POOLING_POLICY.maxRouteDeviationMeters &&
    minAlong >= -0.05 &&
    maxAlong <= POOLING_POLICY.maxRouteOvershootRatio
  );
}

function nearestActivePickupDistanceMeters(activeBookings, candidateMetrics) {
  if (!activeBookings.length || !candidateMetrics) return 0;

  const activeOrigins = activeBookings
    .map((booking) => getBookingEndpoints(booking)?.origin)
    .filter((point) => isValidPoint(point));
  const liveOperatorPoints = activeBookings
    .map((booking) => getOperatorPoint(booking))
    .filter((point) => isValidPoint(point));
  const referencePoints = [...liveOperatorPoints, ...activeOrigins];

  if (!referencePoints.length) return 0;
  return Math.min(
    ...referencePoints.map((point) =>
      haversineDistanceMeters(point, candidateMetrics.endpoints.origin)
    )
  );
}

function normalizedJettyId(value) {
  return asString(value).toLowerCase();
}

function bookingOriginsMatch(a, b) {
  const aJettyId = normalizedJettyId(a?.[BOOKING_FIELDS.originJettyId]);
  const bJettyId = normalizedJettyId(b?.[BOOKING_FIELDS.originJettyId]);
  if (aJettyId && bJettyId && aJettyId === bJettyId) {
    return true;
  }

  const aOrigin = getBookingPoint(a, BOOKING_FIELDS.originCoords);
  const bOrigin = getBookingPoint(b, BOOKING_FIELDS.originCoords);
  return (
    isValidPoint(aOrigin) &&
    isValidPoint(bOrigin) &&
    haversineDistanceMeters(aOrigin, bOrigin) <=
      Math.max(POOLING_POLICY.stopArrivalRadiusMeters * 2, 60)
  );
}

function isSamePickupStillReachable({
  activeBookings,
  candidateBooking,
  liveOperatorPoint,
}) {
  if (!isValidPoint(liveOperatorPoint)) return false;
  const candidateOrigin = getBookingPoint(candidateBooking, BOOKING_FIELDS.originCoords);
  if (!isValidPoint(candidateOrigin)) return false;
  if (
    haversineDistanceMeters(liveOperatorPoint, candidateOrigin) >
    Math.max(POOLING_POLICY.stopArrivalRadiusMeters * 4, 120)
  ) {
    return false;
  }
  return activeBookings.some((activeBooking) =>
    bookingOriginsMatch(activeBooking, candidateBooking)
  );
}

function isSameUncompletedPickupInActivePool(activeBookings, candidateBooking) {
  return activeBookings.some(
    (activeBooking) =>
      !isPassengerAlreadyPickedUp(activeBooking) &&
      bookingOriginsMatch(activeBooking, candidateBooking)
  );
}

function choosePoolCorridor(activeBookings, candidateBooking) {
  const onTheWay = activeBookings.find(
    (booking) => asString(booking[BOOKING_FIELDS.status]) === "on_the_way"
  );
  const base = onTheWay || activeBookings[0] || candidateBooking;
  return buildCorridorFromBooking(base);
}

function routeStopsForBooking(corridor, booking, bookingIndex = 0) {
  const metrics = routeMetricsForBooking(corridor, booking);
  if (!metrics) return [];

  const stops = [];
  if (!isPassengerAlreadyPickedUp(booking)) {
    stops.push({
      bookingIndex,
      type: "pickup",
      alongMeters: metrics.originAlongMeters,
      point: metrics.endpoints.origin,
    });
  }
  stops.push({
    bookingIndex,
    type: "dropoff",
    alongMeters: metrics.destinationAlongMeters,
    point: metrics.endpoints.destination,
  });
  return stops;
}

function routeStopDependencyOrder(a, b) {
  if (a.bookingIndex === b.bookingIndex && a.type !== b.type) {
    return a.type === "pickup" ? -1 : 1;
  }
  const aBookingIds = Array.isArray(a.bookingIds) ? a.bookingIds.map(asString) : [];
  const bBookingIds = Array.isArray(b.bookingIds) ? b.bookingIds.map(asString) : [];
  const sharesBooking = aBookingIds.some((id) => bBookingIds.includes(id));
  if (sharesBooking && a.stopType !== b.stopType) {
    return a.stopType === "pickup" ? -1 : 1;
  }
  return 0;
}

function compareRouteStops(a, b) {
  const dependencyOrder = routeStopDependencyOrder(a, b);
  if (dependencyOrder !== 0) return dependencyOrder;
  if (a.alongMeters !== b.alongMeters) {
    return a.alongMeters - b.alongMeters;
  }
  if (a.type === b.type) return 0;
  return a.type === "pickup" ? -1 : 1;
}

function comparePoolStops(a, b, direction = "forward") {
  const dependencyOrder = routeStopDependencyOrder(a, b);
  if (dependencyOrder !== 0) return dependencyOrder;
  if (a.routePositionMeters !== b.routePositionMeters) {
    return direction === "reverse"
      ? b.routePositionMeters - a.routePositionMeters
      : a.routePositionMeters - b.routePositionMeters;
  }
  if (a.stopType !== b.stopType) {
    return a.stopType === "pickup" ? -1 : 1;
  }
  return asString(a.stopName).localeCompare(asString(b.stopName));
}

function estimateOrderedRouteDistanceMeters(anchor, corridor, bookings) {
  const stops = [];
  for (const booking of bookings) {
    stops.push(...routeStopsForBooking(corridor, booking));
  }

  stops.sort(compareRouteStops);

  let distance = 0;
  let currentAlong = 0;
  const current = anchor || stops[0]?.point || corridor.origin;
  if (isValidPoint(current)) {
    const anchorProjection = projectPointToCorridor(corridor, current);
    currentAlong = anchorProjection.alongMeters;
    distance += anchorProjection.deviationMeters;
  }
  for (const stop of stops) {
    const projectedStop = projectPointToCorridor(corridor, stop.point);
    distance +=
      Math.abs(projectedStop.alongMeters - currentAlong) +
      projectedStop.deviationMeters;
    currentAlong = projectedStop.alongMeters;
  }
  return distance;
}

function orderedPoolStops(corridor, bookings) {
  const stops = [];
  bookings.forEach((booking, bookingIndex) => {
    stops.push(...routeStopsForBooking(corridor, booking, bookingIndex));
  });

  return stops.sort(compareRouteStops);
}

function estimateDropoffArrivalDistances(anchor, corridor, bookings) {
  const stops = orderedPoolStops(corridor, bookings);
  const arrivals = new Map();
  let travelledMeters = 0;
  let currentAlong = 0;
  const current = anchor || stops[0]?.point || corridor.origin;

  if (isValidPoint(current)) {
    const anchorProjection = projectPointToCorridor(corridor, current);
    currentAlong = anchorProjection.alongMeters;
    travelledMeters += anchorProjection.deviationMeters;
  }

  for (const stop of stops) {
    const projectedStop = projectPointToCorridor(corridor, stop.point);
    travelledMeters +=
      Math.abs(projectedStop.alongMeters - currentAlong) +
      projectedStop.deviationMeters;
    currentAlong = projectedStop.alongMeters;

    if (stop.type === "dropoff" && !arrivals.has(stop.bookingIndex)) {
      arrivals.set(stop.bookingIndex, travelledMeters);
    }
  }

  return arrivals;
}

function estimatePerBookingAddedEta(anchor, corridor, activeBookings, allBookings) {
  const activeBaselineArrivals = estimateDropoffArrivalDistances(
    anchor,
    corridor,
    activeBookings
  );
  const pooledArrivals = estimateDropoffArrivalDistances(
    anchor,
    corridor,
    allBookings
  );
  const candidateBaseline = estimateDropoffArrivalDistances(
    anchor,
    corridor,
    [allBookings[allBookings.length - 1]]
  );

  const details = allBookings.map((booking, bookingIndex) => {
    const isCandidate = bookingIndex === allBookings.length - 1;
    const baselineDistance = isCandidate
      ? candidateBaseline.get(0)
      : activeBaselineArrivals.get(bookingIndex);
    const pooledDistance = pooledArrivals.get(bookingIndex);

    if (!Number.isFinite(baselineDistance) || !Number.isFinite(pooledDistance)) {
      return {
        bookingIndex,
        addedEtaMinutes: Number.POSITIVE_INFINITY,
        addedDistanceMeters: Number.POSITIVE_INFINITY,
      };
    }

    const addedDistanceMeters = Math.max(
      0,
      pooledDistance - baselineDistance
    );
    return {
      bookingIndex,
      scope: isCandidate ? "candidate" : "active",
      addedEtaMinutes:
        addedDistanceMeters / POOLING_POLICY.speedMetersPerSecond / 60,
      addedDistanceMeters,
    };
  });

  const maxAddedEtaMinutes = Math.max(
    0,
    ...details.map((detail) => detail.addedEtaMinutes)
  );
  const maxAddedDistanceMeters = Math.max(
    0,
    ...details.map((detail) => detail.addedDistanceMeters)
  );

  return {
    maxAddedEtaMinutes,
    maxAddedDistanceMeters,
    details,
  };
}

function selectRouteAnchor(activeBookings, corridor, candidateBooking) {
  const live = activeBookings
    .map((booking) => getOperatorPoint(booking))
    .find((point) => isValidPoint(point));
  if (live) return live;

  const firstActive = activeBookings[0];
  const firstActiveEndpoints = firstActive ? getBookingEndpoints(firstActive) : null;
  if (firstActiveEndpoints) return firstActiveEndpoints.origin;

  const candidateEndpoints = getBookingEndpoints(candidateBooking);
  return candidateEndpoints?.origin || corridor.origin;
}

function selectSequenceAnchor(activeBookings, corridor, candidateBooking) {
  const onTheWay = activeBookings.find(
    (booking) => asString(booking?.[BOOKING_FIELDS.status]) === "on_the_way"
  );
  const onTheWayDestination = onTheWay
    ? getBookingEndpoints(onTheWay)?.destination
    : null;
  if (isValidPoint(onTheWayDestination)) return onTheWayDestination;
  return selectRouteAnchor(activeBookings, corridor, candidateBooking);
}

function estimateBookingCompletionCost(anchorAlongMeters, corridor, booking) {
  const metrics = routeMetricsForBooking(corridor, booking);
  if (!metrics) return Number.POSITIVE_INFINITY;
  return (
    Math.abs(metrics.originAlongMeters - anchorAlongMeters) +
    Math.max(0, metrics.destinationAlongMeters - metrics.originAlongMeters) +
    metrics.originDeviationMeters +
    metrics.destinationDeviationMeters
  );
}

function routeAwareBookingSort(anchorAlongMeters, corridor) {
  return (a, b) => {
    const aCost = estimateBookingCompletionCost(anchorAlongMeters, corridor, a.data);
    const bCost = estimateBookingCompletionCost(anchorAlongMeters, corridor, b.data);
    if (aCost !== bCost) return aCost - bCost;

    const aMetrics = routeMetricsForBooking(corridor, a.data);
    const bMetrics = routeMetricsForBooking(corridor, b.data);
    const aDestination = aMetrics?.destinationAlongMeters ?? Number.POSITIVE_INFINITY;
    const bDestination = bMetrics?.destinationAlongMeters ?? Number.POSITIVE_INFINITY;
    if (aDestination !== bDestination) return aDestination - bDestination;

    const aCreated = toDate(a.data?.[BOOKING_FIELDS.createdAt])?.getTime() || 0;
    const bCreated = toDate(b.data?.[BOOKING_FIELDS.createdAt])?.getTime() || 0;
    return aCreated - bCreated;
  };
}

function planRouteAwarePoolSequence({ items, corridor, anchor }) {
  const activeItems = items.filter(
    (item) => asString(item.data?.[BOOKING_FIELDS.status]) === "on_the_way"
  );
  const acceptedItems = items.filter(
    (item) => asString(item.data?.[BOOKING_FIELDS.status]) === "accepted"
  );
  const anchorProjection = projectPointToCorridor(
    corridor,
    anchor || corridor.origin
  );
  const anchorAlongMeters = anchorProjection.alongMeters;
  const ordered = [];

  const activeItem = activeItems[0];
  if (activeItem) {
    ordered.push(activeItem);
  }

  ordered.push(
    ...acceptedItems.sort(routeAwareBookingSort(anchorAlongMeters, corridor))
  );

  return ordered.map((item, index) => ({
    ...item,
    poolSequence: index + 1,
  }));
}

function completedStopKeysFromPreviousItems(previousItems = []) {
  const keys = new Set();
  for (const item of previousItems) {
    const stopPlan = item?.data?.[BOOKING_FIELDS.poolStopPlan];
    if (!Array.isArray(stopPlan)) continue;
    for (const stop of stopPlan) {
      const status = asString(stop.status);
      if (status !== "completed" && status !== "skipped") continue;
      const bookingIds = Array.isArray(stop.bookingIds) ? stop.bookingIds : [];
      for (const bookingId of bookingIds) {
        keys.add(`${asString(stop.stopType)}|${asString(bookingId)}`);
      }
    }
  }
  return keys;
}

function passengerTotalsForBookingIds(bookingIds = [], bookingTotals = new Map()) {
  const totals = {
    passengerCount: 0,
    adultCount: 0,
    childCount: 0,
  };
  for (const bookingId of bookingIds) {
    const itemTotals = bookingTotals.get(asString(bookingId));
    if (!itemTotals) continue;
    totals.passengerCount += itemTotals.passengerCount;
    totals.adultCount += itemTotals.adultCount;
    totals.childCount += itemTotals.childCount;
  }
  return totals;
}

function completedStopsFromPreviousItems(
  previousItems = [],
  activeIds = new Set(),
  bookingTotals = new Map()
) {
  const seen = new Set();
  const stops = [];
  for (const item of previousItems) {
    const stopPlan = item?.data?.[BOOKING_FIELDS.poolStopPlan];
    if (!Array.isArray(stopPlan)) continue;
    for (const stop of stopPlan) {
      const status = asString(stop.status);
      if (status !== "completed" && status !== "skipped") continue;
      const bookingIds = Array.isArray(stop.bookingIds)
        ? stop.bookingIds.map(asString).filter((id) => activeIds.has(id))
        : [];
      if (bookingIds.length === 0) continue;
      const key = `${asString(stop.stopType)}|${asString(stop.stopName)}|${bookingIds.sort().join(",")}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const fallbackTotals = passengerTotalsForBookingIds(bookingIds, bookingTotals);
      const passengerCount = asNonNegativeInt(
        stop.passengerCount,
        fallbackTotals.passengerCount
      );
      const adultCount = asNonNegativeInt(stop.adultCount, fallbackTotals.adultCount);
      const childCount = asNonNegativeInt(stop.childCount, fallbackTotals.childCount);
      stops.push({
        ...stop,
        bookingIds,
        passengerCount,
        adultCount,
        childCount,
        status,
      });
    }
  }
  return stops;
}

function resolvePoolRouteDirection(items, corridor, fallbackDirection = "") {
  for (const item of items) {
    const explicit = normalizeRouteDirection(
      item?.data?.[BOOKING_FIELDS.routeDirection]
    );
    if (explicit) return explicit;
  }
  for (const item of items) {
    const metrics = routeMetricsForBooking(corridor, item?.data || {});
    const inferred = routeDirectionForMetrics(metrics);
    if (inferred) return inferred;
  }
  return normalizeRouteDirection(fallbackDirection) || "forward";
}

function buildPoolStopPlan({
  items,
  corridor,
  previousItems = [],
  routeDirection = "",
}) {
  const activeIds = new Set(items.map((item) => asString(item.id)));
  const completedKeys = completedStopKeysFromPreviousItems(previousItems);
  const bookingTotals = new Map();
  for (const item of items) {
    const booking = item.data || {};
    const bookingId = asString(item.id || booking[BOOKING_FIELDS.bookingId]);
    if (!bookingId) continue;
    const adultCount = asNonNegativeInt(booking[BOOKING_FIELDS.adultCount]);
    const childCount = asNonNegativeInt(booking[BOOKING_FIELDS.childCount]);
    const fallbackPassengerCount = adultCount + childCount;
    bookingTotals.set(bookingId, {
      passengerCount: asNonNegativeInt(
        booking[BOOKING_FIELDS.passengerCount],
        fallbackPassengerCount > 0 ? fallbackPassengerCount : 1
      ),
      adultCount,
      childCount,
    });
  }
  const completedStops = completedStopsFromPreviousItems(
    previousItems,
    activeIds,
    bookingTotals
  );
  const grouped = new Map();
  const direction = resolvePoolRouteDirection(items, corridor, routeDirection);

  for (const item of items) {
    const booking = item.data || {};
    const bookingId = asString(item.id || booking[BOOKING_FIELDS.bookingId]);
    if (!bookingId) continue;
    const metrics = routeMetricsForBooking(corridor, booking);
    if (!metrics) continue;

    const endpoints = getBookingEndpoints(booking);
    if (!endpoints) continue;

    const stops = [
      {
        stopType: "pickup",
        stopName: asString(booking[BOOKING_FIELDS.origin]),
        jettyId: asString(booking.originJettyId),
        point: endpoints.origin,
        routePositionMeters: metrics.originAlongMeters,
      },
      {
        stopType: "dropoff",
        stopName: asString(booking[BOOKING_FIELDS.destination]),
        jettyId: asString(booking.destinationJettyId),
        point: endpoints.destination,
        routePositionMeters: metrics.destinationAlongMeters,
      },
    ];

    for (const stop of stops) {
      if (completedKeys.has(`${stop.stopType}|${bookingId}`)) continue;
      const key = `${stop.stopType}|${stop.jettyId || stop.stopName}|${Math.round(stop.routePositionMeters)}`;
      const existing = grouped.get(key) || {
        stopType: stop.stopType,
        stopName: stop.stopName,
        jettyId: stop.jettyId,
        lat: stop.point.lat,
        lng: stop.point.lng,
        routePositionMeters: stop.routePositionMeters,
        bookingIds: [],
        passengerCount: 0,
        adultCount: 0,
        childCount: 0,
        status: "pending",
      };
      existing.bookingIds.push(bookingId);
      const totals = bookingTotals.get(bookingId) || {
        passengerCount: 1,
        adultCount: 0,
        childCount: 0,
      };
      existing.passengerCount += totals.passengerCount;
      existing.adultCount += totals.adultCount;
      existing.childCount += totals.childCount;
      grouped.set(key, existing);
    }
  }

  const pendingStops = [...grouped.values()].sort((a, b) =>
    comparePoolStops(a, b, direction)
  );

  return [...completedStops, ...pendingStops].map((stop, index) => ({
    stopId:
      asString(stop.stopId) ||
      `${stop.stopType}_${asString(stop.jettyId || stop.stopName).replace(/\W+/g, "_").toLowerCase()}_${index + 1}`,
    stopIndex: index,
    stopType: stop.stopType,
    jettyId: stop.jettyId || stop.stopJettyId || null,
    jettyName: stop.stopName || stop.jettyName || "",
    stopName: stop.stopName || stop.jettyName || "",
    lat: Number(stop.lat || 0),
    lng: Number(stop.lng || 0),
    routePositionMeters: Number(stop.routePositionMeters || 0),
    bookingIds: [...new Set(stop.bookingIds)].sort(),
    passengerCount: asNonNegativeInt(stop.passengerCount),
    adultCount: asNonNegativeInt(stop.adultCount),
    childCount: asNonNegativeInt(stop.childCount),
    status: stop.status || "pending",
    reachedAt: stop.reachedAt || null,
    completedAt: stop.completedAt || null,
  }));
}

function resolveCurrentStopIndex(stopPlan) {
  return Math.max(
    0,
    stopPlan.findIndex(
      (stop) => stop.status !== "completed" && stop.status !== "skipped"
    )
  );
}

function applyCurrentStopState(stopPlan, currentStopIndex) {
  return stopPlan.map((stop, index) => {
    if (stop.status === "completed" || stop.status === "skipped") {
      return stop;
    }
    return {
      ...stop,
      status: index === currentStopIndex ? "active" : "pending",
    };
  });
}

function currentStopFromPlan(stopPlan) {
  return (
    stopPlan.find((stop) => stop.status === "active") ||
    stopPlan.find(
      (stop) => stop.status !== "completed" && stop.status !== "skipped"
    ) ||
    null
  );
}

function canStartBookingAtCurrentPoolStop(stopPlan, bookingId) {
  const currentStop = currentStopFromPlan(stopPlan);
  const currentStopBookingIds = Array.isArray(currentStop?.bookingIds)
    ? currentStop.bookingIds.map(asString).filter((id) => id.length > 0)
    : [];
  if (currentStopBookingIds.length === 0) {
    return null;
  }
  return currentStopBookingIds.includes(asString(bookingId));
}

function startableBookingIdAtCurrentPoolStop(stopPlan, acceptedIds = new Set()) {
  const currentStop = currentStopFromPlan(stopPlan);
  const currentStopBookingIds = Array.isArray(currentStop?.bookingIds)
    ? currentStop.bookingIds.map(asString).filter((id) => id.length > 0)
    : [];
  for (const bookingId of currentStopBookingIds) {
    if (acceptedIds.has(bookingId)) {
      return bookingId;
    }
  }
  return null;
}

function canCompleteCurrentPoolStopWithBooking(
  stopPlan,
  bookingId,
  activePoolHandleIds = new Set()
) {
  const currentStop = currentStopFromPlan(stopPlan);
  const currentStopBookingIds = Array.isArray(currentStop?.bookingIds)
    ? currentStop.bookingIds.map(asString).filter((id) => id.length > 0)
    : [];
  const requestedBookingId = asString(bookingId);
  if (currentStopBookingIds.length === 0 || !requestedBookingId) {
    return null;
  }
  return (
    currentStopBookingIds.includes(requestedBookingId) ||
    activePoolHandleIds.has(requestedBookingId)
  );
}

function shouldEnforceActivePoolPickupWindow({ hasActiveTrip } = {}) {
  return hasActiveTrip !== true;
}

function poolStopStatePayload(stopPlan, poolStatus = "in_progress") {
  const currentStopIndex = resolveCurrentStopIndex(stopPlan);
  const plannedStops = applyCurrentStopState(stopPlan, currentStopIndex);
  const currentStop = currentStopFromPlan(plannedStops);
  return {
    plannedStops,
    currentStopIndex,
    currentStopId: currentStop?.stopId || null,
    poolStatus,
  };
}

function bookingStopIdsFromPlan(stopPlan, bookingId) {
  const normalizedBookingId = asString(bookingId);
  let pickupStopId = null;
  let dropoffStopId = null;
  for (const stop of stopPlan) {
    const bookingIds = Array.isArray(stop.bookingIds)
      ? stop.bookingIds.map(asString)
      : [];
    if (!bookingIds.includes(normalizedBookingId)) continue;
    if (asString(stop.stopType) === "pickup") {
      pickupStopId = asString(stop.stopId);
    }
    if (asString(stop.stopType) === "dropoff") {
      dropoffStopId = asString(stop.stopId);
    }
  }
  return { pickupStopId, dropoffStopId };
}

async function replanRouteAwarePoolForOperator({
  operatorUid,
  anchorBooking = null,
  reason = "pool_replan",
}) {
  const normalizedOperatorUid = asString(operatorUid);
  if (!normalizedOperatorUid) return { updated: 0 };

  const activeSnap = await db
    .collection(COLLECTIONS.bookings)
    .where(BOOKING_FIELDS.operatorUid, "==", normalizedOperatorUid)
    .where(BOOKING_FIELDS.status, "in", ["accepted", "on_the_way"])
    .get();

  const items = activeSnap.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    data: doc.data() || {},
  }));
  const acceptedCount = items.filter(
    (item) => asString(item.data?.[BOOKING_FIELDS.status]) === "accepted"
  ).length;
  if (items.length === 0 || acceptedCount === 0) {
    return { updated: 0 };
  }

  const corridor = choosePoolCorridor(
    items.map((item) => item.data),
    anchorBooking || items[0].data
  );
  if (!corridor) {
    logger.warn("Skipping pooled sequence replan due to missing corridor", {
      operatorUid: normalizedOperatorUid,
      reason,
    });
    return { updated: 0 };
  }

  const anchorBookingDestination = anchorBooking
    ? getBookingEndpoints(anchorBooking)?.destination
    : null;
  const anchor =
    anchorBookingDestination ||
    selectSequenceAnchor(
      items.map((item) => item.data),
      corridor,
      anchorBooking || items[0].data
    );
  const sequencePlan = planRouteAwarePoolSequence({
    items,
    corridor,
    anchor,
  });
  const stopPlan = buildPoolStopPlan({
    items: sequencePlan,
    corridor,
    previousItems: items,
  });
  const hasActiveTrip = items.some(
    (item) => asString(item.data?.[BOOKING_FIELDS.status]) === "on_the_way"
  );
  const stopState = poolStopStatePayload(
    stopPlan,
    hasActiveTrip ? "in_progress" : "accepted"
  );

  const batch = db.batch();
  let updated = 0;
  for (const item of sequencePlan) {
    const currentSequence = Number(
      item.data?.[BOOKING_FIELDS.poolSequence] || 0
    );
    const status = asString(item.data?.[BOOKING_FIELDS.status]);
    const payload = {
      [BOOKING_FIELDS.poolSequence]: item.poolSequence,
      [BOOKING_FIELDS.poolCriteriaVersion]: POOLING_POLICY.criteriaVersion,
      [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
      [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
      [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
      [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
      [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
    };
    const stopIds = bookingStopIdsFromPlan(stopState.plannedStops, item.id);
    payload[BOOKING_FIELDS.poolPickupStopId] = stopIds.pickupStopId;
    payload[BOOKING_FIELDS.poolDropoffStopId] = stopIds.dropoffStopId;
    if (status === "accepted") {
      payload[BOOKING_FIELDS.pooled] = true;
      payload[BOOKING_FIELDS.poolMax] = POOLING_POLICY.maxConcurrent;
    }
    if (
      currentSequence !== item.poolSequence ||
      asString(item.data?.[BOOKING_FIELDS.poolCriteriaVersion]) !==
        POOLING_POLICY.criteriaVersion ||
      JSON.stringify(item.data?.[BOOKING_FIELDS.poolStopPlan] || []) !==
        JSON.stringify(stopState.plannedStops)
    ) {
      batch.update(item.ref, payload);
      updated += 1;
    }
  }

  if (updated > 0) {
    await batch.commit();
  }

  logger.info("Route-aware pooled sequence replanned", {
    operatorUid: normalizedOperatorUid,
    reason,
    updated,
    remaining: items.length,
  });

  return { updated };
}

function evaluatePoolingEligibility(
  activeBookings,
  candidateBooking,
  { operatorPoint = null, requestedRouteDirection = "" } = {}
) {
  const corridor = choosePoolCorridor(activeBookings, candidateBooking);
  if (!corridor) {
    return {
      eligible: false,
      reason: "missing_coordinates",
    };
  }

  const allBookings = [...activeBookings, candidateBooking];
  const metrics = allBookings.map((booking) =>
    routeMetricsForBooking(corridor, booking)
  );
  const candidateMetrics = routeMetricsForBooking(corridor, candidateBooking);
  const activeRouteDirection =
    currentSweepDirection(activeBookings) ||
    routeDirectionForMetrics(
      routeMetricsForBooking(corridor, activeBookings[0] || null)
    );
  const requestedDirection = normalizeRouteDirection(requestedRouteDirection);
  const routeDirection =
    activeRouteDirection ||
    requestedDirection ||
    routeDirectionForMetrics(candidateMetrics);
  const sameUncompletedPickupInActivePool =
    isSameUncompletedPickupInActivePool(activeBookings, candidateBooking);
  const hasActivePool = activeBookings.length > 0;

  if (
    activeRouteDirection &&
    requestedDirection &&
    activeRouteDirection !== requestedDirection &&
    !sameUncompletedPickupInActivePool
  ) {
    return {
      eligible: false,
      reason: "mixed_route_direction_not_allowed",
      corridor,
      routeDirection: activeRouteDirection,
      candidateMetrics,
    };
  }

  if (
    hasActivePool &&
    !isBookingDirectionValidForPool(candidateMetrics, routeDirection) &&
    !sameUncompletedPickupInActivePool
  ) {
    return {
      eligible: false,
      reason: "reverse_direction",
      corridor,
      routeDirection,
      candidateMetrics,
    };
  }

  if (metrics.some((metric) => !isBookingWithinCorridor(metric))) {
    return {
      eligible: false,
      reason: "outside_route_corridor",
      corridor,
      routeDirection,
      candidateMetrics,
    };
  }

  const eligibilityAnchor = selectEligibilityAnchorPoint(
    activeBookings,
    operatorPoint
  );
  const liveOperatorPoint = eligibilityAnchor.point;
  const hasLiveOperatorAnchor =
    eligibilityAnchor.source === "request_operator" ||
    eligibilityAnchor.source === "stored_operator";
  let operatorProjection = null;
  let candidatePickupAheadOfOperator = false;
  let candidatePickupRouteAheadDistanceMeters = 0;
  if (activeBookings.length > 0 && liveOperatorPoint && candidateMetrics) {
    operatorProjection = projectPointToCorridor(corridor, liveOperatorPoint);
    candidatePickupRouteAheadDistanceMeters =
      routeDirection === "reverse"
        ? operatorProjection.alongMeters - candidateMetrics.originAlongMeters
        : candidateMetrics.originAlongMeters - operatorProjection.alongMeters;
    candidatePickupAheadOfOperator =
      candidatePickupRouteAheadDistanceMeters > 0;
    const pickupBehindOperator =
      routeDirection === "reverse"
        ? candidateMetrics.originAlongMeters >= operatorProjection.alongMeters
        : candidateMetrics.originAlongMeters <= operatorProjection.alongMeters;
    const samePickupStillReachable = isSamePickupStillReachable({
      activeBookings,
      candidateBooking,
      liveOperatorPoint: hasLiveOperatorAnchor ? liveOperatorPoint : null,
    });
    const samePickupProjectionJitter =
      sameUncompletedPickupInActivePool &&
      Math.abs(
        candidateMetrics.originAlongMeters - operatorProjection.alongMeters
      ) <= 250;
    if (pickupBehindOperator && !samePickupStillReachable) {
      if (!samePickupProjectionJitter) {
        return {
          eligible: false,
          reason: "pickup_behind_operator",
          corridor,
          routeDirection,
          operatorAnchorSource: eligibilityAnchor.source,
          operatorRoutePositionMeters: operatorProjection.alongMeters,
          candidateMetrics,
        };
      }
    }
    if (samePickupStillReachable || samePickupProjectionJitter) {
      candidatePickupAheadOfOperator = true;
      candidatePickupRouteAheadDistanceMeters = Math.max(
        0,
        candidatePickupRouteAheadDistanceMeters
      );
    }
  }

  if (activeBookings.length >= POOLING_POLICY.maxConcurrent) {
    return {
      eligible: false,
      reason: "max_pool_reached",
      corridor,
      routeDirection,
      candidateMetrics,
    };
  }

  const anchor = selectRouteAnchor(activeBookings, corridor, candidateBooking);
  const activeDistance = activeBookings.length
    ? estimateOrderedRouteDistanceMeters(anchor, corridor, activeBookings)
    : 0;
  const pooledDistance = estimateOrderedRouteDistanceMeters(
    anchor,
    corridor,
    allBookings
  );
  const addedDistanceMeters = Math.max(0, pooledDistance - activeDistance);
  const addedEtaMinutes =
    addedDistanceMeters / POOLING_POLICY.speedMetersPerSecond / 60;
  const riderImpact = estimatePerBookingAddedEta(
    anchor,
    corridor,
    activeBookings,
    allBookings
  );

  if (
    activeBookings.length > 0 &&
    riderImpact.maxAddedEtaMinutes > POOLING_POLICY.addedEtaLimitMinutes
  ) {
    return {
      eligible: false,
      reason: "added_eta_exceeded",
      corridor,
      routeDirection,
      addedDistanceMeters,
      addedEtaMinutes,
      maxPerRiderAddedEtaMinutes: riderImpact.maxAddedEtaMinutes,
      maxPerRiderAddedDistanceMeters: riderImpact.maxAddedDistanceMeters,
      candidateMetrics: routeMetricsForBooking(corridor, candidateBooking),
    };
  }

  const pickupDistanceToPoolMeters = nearestActivePickupDistanceMeters(
    activeBookings,
    candidateMetrics
  );
  if (
    activeBookings.length > 0 &&
    pickupDistanceToPoolMeters > POOLING_POLICY.maxPickupDistanceMeters &&
    !candidatePickupAheadOfOperator
  ) {
    return {
      eligible: false,
      reason: "pickup_distance_exceeded",
      corridor,
      routeDirection,
      pickupDistanceToPoolMeters,
      candidateMetrics,
    };
  }

  const score =
    (candidateMetrics.originDeviationMeters +
      candidateMetrics.destinationDeviationMeters +
      pickupDistanceToPoolMeters +
      addedDistanceMeters) /
    1000;

  return {
    eligible: true,
    reason: "eligible",
    corridor,
    routeDirection,
    activeDistanceMeters: activeDistance,
    pooledDistanceMeters: pooledDistance,
    addedDistanceMeters,
    addedEtaMinutes,
    maxPerRiderAddedEtaMinutes: riderImpact.maxAddedEtaMinutes,
    maxPerRiderAddedDistanceMeters: riderImpact.maxAddedDistanceMeters,
    pickupDistanceToPoolMeters,
    candidatePickupRouteAheadDistanceMeters,
    score: Math.max(0, Math.min(1, 1 / (1 + score))),
    candidateMetrics,
  };
}

function isCurrentSweepDeferralReason(reason) {
  return [
    "pickup_behind_operator",
    "reverse_direction",
    "mixed_route_direction_not_allowed",
    "route_ahead_distance_exceeded",
    "pickup_distance_exceeded",
  ].includes(asString(reason));
}

function currentSweepDirection(activeBookings) {
  return (
    activeBookings
      .map((booking) => asString(booking?.[BOOKING_FIELDS.routeDirection]))
      .find((direction) => direction === "forward" || direction === "reverse") ||
    ""
  );
}

function currentSweepPoolGroupId(activeBookings) {
  return (
    activeBookings
      .map((booking) => asString(booking?.[BOOKING_FIELDS.poolGroupId]))
      .find((poolGroupId) => poolGroupId.length > 0) || ""
  );
}

function deferBookingForCurrentSweep({
  tx,
  bookingRef,
  operatorUid,
  activeBookings,
  reason,
  now,
}) {
  const deferUntil = new Date(
    now.getTime() + POOLING_POLICY.nextSweepDeferMinutes * 60 * 1000
  );
  tx.update(bookingRef, {
    [BOOKING_FIELDS.poolDeferredForOperatorUid]: operatorUid,
    [BOOKING_FIELDS.poolDeferredRouteDirection]: currentSweepDirection(activeBookings),
    [BOOKING_FIELDS.poolDeferredPoolGroupId]: currentSweepPoolGroupId(activeBookings),
    [BOOKING_FIELDS.poolDeferredReason]: asString(reason) || "not_for_current_sweep",
    [BOOKING_FIELDS.poolDeferredUntil]: deferUntil,
    [BOOKING_FIELDS.poolDeferredAt]: FieldValue.serverTimestamp(),
    [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
  });

  logger.info("Pooled booking deferred for later route sweep", {
    operatorUid,
    reason: asString(reason) || "not_for_current_sweep",
    deferredUntil: deferUntil.toISOString(),
    currentSweepDirection: currentSweepDirection(activeBookings),
    currentSweepPoolGroupId: currentSweepPoolGroupId(activeBookings),
  });

  return {
    status: "deferred",
    reason: asString(reason) || "not_for_current_sweep",
    message:
      "This request is queued for a later route sweep. It will stay available when your direction changes.",
    deferredUntil: deferUntil.toISOString(),
  };
}

function appendStatusHistory({
  tx,
  bookingRef,
  from,
  to,
  changedBy,
  source = "operator_app",
}) {
  tx.set(bookingRef.collection(BOOKING_SUBCOLLECTIONS.statusHistory).doc(), {
    [STATUS_HISTORY_FIELDS.from]: from,
    [STATUS_HISTORY_FIELDS.to]: to,
    [STATUS_HISTORY_FIELDS.changedBy]: changedBy,
    [STATUS_HISTORY_FIELDS.source]: source,
    [STATUS_HISTORY_FIELDS.timestamp]: FieldValue.serverTimestamp(),
  });
}

function buildPickupStopUpdatePayload({
  item,
  stopBookingIds,
  stopState,
  stopIds,
  hasOperatorLocation = false,
  operatorLat,
  operatorLng,
  fieldValue = FieldValue,
}) {
  const isAtStop = stopBookingIds.has(item.id);
  const payload = {
    [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
    [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
    [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
    [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
    [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
    [BOOKING_FIELDS.poolPickupStopId]: stopIds.pickupStopId,
    [BOOKING_FIELDS.poolDropoffStopId]: stopIds.dropoffStopId,
    [BOOKING_FIELDS.updatedAt]: fieldValue.serverTimestamp(),
  };
  if (isAtStop) {
    payload[BOOKING_FIELDS.status] = "on_the_way";
    payload[BOOKING_FIELDS.passengerPickedUpAt] =
      fieldValue.serverTimestamp();
    payload[BOOKING_FIELDS.pickedUpAt] = fieldValue.serverTimestamp();
    payload[BOOKING_FIELDS.poolPhase] = "onboard";
    payload[BOOKING_FIELDS.onboard] = true;
  }
  if (hasOperatorLocation) {
    payload[BOOKING_FIELDS.operatorLat] = operatorLat;
    payload[BOOKING_FIELDS.operatorLng] = operatorLng;
  }
  return { payload, isAtStop };
}

async function rejectStalePendingBookingsWithoutOnlineOperators({
  firestore = db,
  now = new Date(),
  log = logger,
  fieldValue = FieldValue,
} = {}) {
  const onlineOperators = await firestore
    .collection(COLLECTIONS.operatorPresence)
    .where("isOnline", "==", true)
    .limit(1)
    .get();

  if (!onlineOperators.empty) {
    const summary = {
      onlineOperatorsPresent: true,
      scanned: 0,
      rejected: 0,
      skipped: 0,
    };
    log.info("Pending no-operator cleanup skipped", summary);
    return summary;
  }

  const cutoff = new Date(
    now.getTime() - PENDING_NO_OPERATOR_POLICY.timeoutMinutes * 60 * 1000
  );
  const snapshot = await firestore
    .collection(COLLECTIONS.bookings)
    .where(BOOKING_FIELDS.status, "==", "pending")
    .where(BOOKING_FIELDS.createdAt, "<=", cutoff)
    .limit(PENDING_NO_OPERATOR_POLICY.batchLimit)
    .get();

  if (snapshot.empty) {
    const summary = {
      onlineOperatorsPresent: false,
      scanned: 0,
      rejected: 0,
      skipped: 0,
      cutoff: cutoff.toISOString(),
    };
    log.info("Pending no-operator cleanup completed", summary);
    return summary;
  }

  const batch = firestore.batch();
  let rejected = 0;
  let skipped = 0;

  for (const doc of snapshot.docs) {
    const booking = doc.data() || {};
    const status = asString(booking[BOOKING_FIELDS.status]).toLowerCase();
    const operatorUid = asString(booking[BOOKING_FIELDS.operatorUid]);

    if (status !== "pending" || operatorUid) {
      skipped += 1;
      continue;
    }

    batch.update(doc.ref, {
      [BOOKING_FIELDS.status]: "rejected",
      [BOOKING_FIELDS.updatedAt]: fieldValue.serverTimestamp(),
    });
    appendStatusHistory({
      tx: batch,
      bookingRef: doc.ref,
      from: "pending",
      to: "rejected",
      changedBy: PENDING_NO_OPERATOR_POLICY.changedBy,
      source: PENDING_NO_OPERATOR_POLICY.source,
    });
    rejected += 1;
  }

  if (rejected > 0) {
    await batch.commit();
  }

  const summary = {
    onlineOperatorsPresent: false,
    scanned: snapshot.size,
    rejected,
    skipped,
    cutoff: cutoff.toISOString(),
    hasMoreEligibleDocs:
      snapshot.size >= PENDING_NO_OPERATOR_POLICY.batchLimit,
  };
  log.info("Pending no-operator cleanup completed", summary);
  return summary;
}

function normalizeOperatorDisplayId(value) {
  return asString(value).toUpperCase();
}

exports.saveOperatorProfile = onCall(
  {
    region: "asia-southeast1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const uid = request.auth.uid;
    const name = asString(request.data?.name);
    const email = asString(request.data?.email);
    const operatorId = normalizeOperatorDisplayId(request.data?.operatorId);
    const phoneNumber = asString(request.data?.phoneNumber);

    if (!name || !email || !operatorId || !phoneNumber) {
      throw new HttpsError(
        "invalid-argument",
        "Name, email, operator ID, and phone number are required."
      );
    }

    const operatorRef = db.collection(COLLECTIONS.operators).doc(uid);
    const presenceRef = db.collection(COLLECTIONS.operatorPresence).doc(uid);
    const operatorIdIndexRef = db
      .collection(COLLECTIONS.operatorIdIndex)
      .doc(operatorId);
    const duplicateOperatorIdQuery = db
      .collection(COLLECTIONS.operators)
      .where("operatorId", "==", operatorId)
      .limit(2);

    await db.runTransaction(async (tx) => {
      const [
        operatorSnap,
        presenceSnap,
        operatorIdIndexSnap,
        duplicateOperatorIdSnap,
      ] = await Promise.all([
        tx.get(operatorRef),
        tx.get(presenceRef),
        tx.get(operatorIdIndexRef),
        tx.get(duplicateOperatorIdQuery),
      ]);

      duplicateOperatorIdSnap.docs.forEach((doc) => {
        if (doc.id !== uid) {
          throw new HttpsError(
            "already-exists",
            `Operator ID ${operatorId} is already used.`
          );
        }
      });

      if (operatorIdIndexSnap.exists) {
        const claimedBy = asString(operatorIdIndexSnap.data()?.uid);
        if (claimedBy && claimedBy !== uid) {
          throw new HttpsError(
            "already-exists",
            `Operator ID ${operatorId} is already used.`
          );
        }
      }

      const existingOperator = operatorSnap.data() || {};
      const previousOperatorId = normalizeOperatorDisplayId(
        existingOperator.operatorId
      );
      const presenceData = presenceSnap.data() || {};
      const resolvedOnline = presenceData.isOnline === true;

      tx.set(
        operatorRef,
        {
          name,
          email,
          operatorId,
          phoneNumber,
          updatedAt: FieldValue.serverTimestamp(),
          ...(!operatorSnap.exists
            ? { createdAt: FieldValue.serverTimestamp() }
            : {}),
        },
        { merge: true }
      );

      tx.set(
        operatorIdIndexRef,
        {
          uid,
          operatorId,
          updatedAt: FieldValue.serverTimestamp(),
          ...(!operatorIdIndexSnap.exists
            ? { createdAt: FieldValue.serverTimestamp() }
            : {}),
        },
        { merge: true }
      );

      if (previousOperatorId && previousOperatorId !== operatorId) {
        tx.delete(
          db.collection(COLLECTIONS.operatorIdIndex).doc(previousOperatorId)
        );
      }

      tx.set(
        presenceRef,
        {
          isOnline: resolvedOnline,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    return {
      status: "saved",
      operatorId,
    };
  }
);

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
  const normalizedCurrency = currency.trim().toLowerCase();
  const minimumCharge = MINIMUM_STRIPE_CHARGE_BY_CURRENCY[normalizedCurrency];
  if (minimumCharge != null && amount < minimumCharge) {
    return {
      valid: false,
      error: `${normalizedCurrency.toUpperCase()} payments must be at least ${minimumCharge.toFixed(2)}`,
    };
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
  const normalizedCurrency = String(currency || "").trim().toLowerCase();
  const minimumCharge = MINIMUM_STRIPE_CHARGE_BY_CURRENCY[normalizedCurrency];
  if (minimumCharge != null && amountInMinorUnit < Math.round(minimumCharge * 100)) {
    throw new Error(`${normalizedCurrency.toUpperCase()} payments must be at least ${minimumCharge.toFixed(2)}`);
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
 * Accepts a booking into a pooled queue for the authenticated operator.
 * Applies MVP pooling thresholds and assigns poolGroupId/poolSequence.
 */
exports.acceptPooledBooking = onCall(
  {
    region: "asia-southeast1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const operatorUid = request.auth.uid;
    const operatorRef = db.collection(COLLECTIONS.operators).doc(operatorUid);
    const bookingRef = db.collection(COLLECTIONS.bookings).doc(bookingId);
    const now = new Date();
    const nowIso = now.toISOString();

    return db.runTransaction(async (tx) => {
      const [operatorSnap, bookingSnap] = await Promise.all([
        tx.get(operatorRef),
        tx.get(bookingRef),
      ]);

      if (!operatorSnap.exists) {
        throw new HttpsError(
          "permission-denied",
          "Operator profile is required to accept bookings."
        );
      }

      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const booking = await hydrateBookingRouteGeometry(
        tx,
        bookingSnap.data() || {}
      );
      const status = asString(booking[BOOKING_FIELDS.status]);
      if (status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "Booking is no longer pending."
        );
      }

      const assignedOperator =
        asString(booking[BOOKING_FIELDS.operatorUid]) ||
        asString(booking[BOOKING_FIELDS.operatorId]);
      if (assignedOperator) {
        throw new HttpsError(
          "failed-precondition",
          "Booking is already assigned to another operator."
        );
      }

      const rejectedBy = Array.isArray(booking[BOOKING_FIELDS.rejectedBy])
        ? booking[BOOKING_FIELDS.rejectedBy]
        : [];
      if (rejectedBy.includes(operatorUid)) {
        throw new HttpsError(
          "failed-precondition",
          "You already rejected this booking."
        );
      }

      const createdAt = toDate(booking[BOOKING_FIELDS.createdAt]);
      if (
        createdAt &&
        !isWithinMinutes(createdAt, now, POOLING_POLICY.pickupWindowMinutes)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Booking request is older than the pooling pickup window."
        );
      }

      const activeQuery = db
        .collection(COLLECTIONS.bookings)
        .where(BOOKING_FIELDS.operatorUid, "==", operatorUid)
        .where(BOOKING_FIELDS.status, "in", ["accepted", "on_the_way"]);

      const activeSnap = await tx.get(activeQuery);
      const activeDocs = activeSnap.docs;
      const activeBookings = await hydrateBookingsRouteGeometry(
        tx,
        activeDocs.map((doc) => doc.data() || {})
      );
      const onTheWayDocs = activeDocs.filter(
        (doc) => asString(doc.data()?.[BOOKING_FIELDS.status]) === "on_the_way"
      );
      if (onTheWayDocs.length > 1) {
        throw new HttpsError(
          "failed-precondition",
          "Operator has more than one active on-the-way booking."
        );
      }
      const hasActiveTrip = onTheWayDocs.length === 1;

      const activeCreatedTimes = activeBookings
        .map((activeBooking) =>
          toDate(activeBooking[BOOKING_FIELDS.createdAt])?.getTime()
        )
        .filter((millis) => Number.isFinite(millis));
      if (
        createdAt &&
        activeCreatedTimes.length > 0 &&
        shouldEnforceActivePoolPickupWindow({ hasActiveTrip })
      ) {
        const earliestActiveCreatedAt = new Date(Math.min(...activeCreatedTimes));
        if (
          !isWithinMinutes(
            createdAt,
            earliestActiveCreatedAt,
            POOLING_POLICY.pickupWindowMinutes
          )
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Booking is outside the pre-start pooling pickup window."
          );
        }
      }

      if (activeDocs.length >= POOLING_POLICY.maxConcurrent) {
        throw new HttpsError(
          "failed-precondition",
          "Maximum pooled booking limit reached."
        );
      }

      const requestOperatorPoint = {
        lat: Number(request.data?.operatorLat),
        lng: Number(request.data?.operatorLng),
      };
      const eligibility = evaluatePoolingEligibility(activeBookings, booking, {
        operatorPoint: isValidPoint(requestOperatorPoint)
          ? requestOperatorPoint
          : null,
        requestedRouteDirection: request.data?.routeDirection,
      });
      if (!eligibility.eligible) {
        logger.info("Pooled booking rejected by eligibility check", {
          bookingId,
          operatorUid,
          reason: eligibility.reason,
          routeDirection: eligibility.routeDirection,
          candidateMetrics: eligibility.candidateMetrics,
          pickupDistanceToPoolMeters: eligibility.pickupDistanceToPoolMeters,
          addedEtaMinutes: eligibility.addedEtaMinutes,
          maxPerRiderAddedEtaMinutes: eligibility.maxPerRiderAddedEtaMinutes,
        });
        if (isCurrentSweepDeferralReason(eligibility.reason)) {
          return deferBookingForCurrentSweep({
            tx,
            bookingRef,
            operatorUid,
            activeBookings,
            reason: eligibility.reason,
            now,
          });
        }
        throw new HttpsError(
          "failed-precondition",
          "Booking is not eligible for pooling with the current route."
        );
      }

      let poolGroupId = "";
      for (const doc of activeDocs) {
        const data = doc.data() || {};
        const existingGroup = asString(data[BOOKING_FIELDS.poolGroupId]);
        if (existingGroup) {
          poolGroupId = existingGroup;
          break;
        }
      }

      if (!poolGroupId) {
        poolGroupId = db.collection(COLLECTIONS.bookings).doc().id;
      }

      const operatorData = operatorSnap.data() || {};
      const acceptedBooking = {
        ...booking,
        [BOOKING_FIELDS.status]: "accepted",
        [BOOKING_FIELDS.operatorUid]: operatorUid,
        [BOOKING_FIELDS.routeDirection]: eligibility.routeDirection,
      };
      const activeItems = activeDocs.map((doc, index) => ({
        id: doc.id,
        ref: doc.ref,
        data: activeBookings[index] || doc.data() || {},
      }));
      const sequencePlan = planRouteAwarePoolSequence({
        items: [
          ...activeItems,
          {
            id: bookingId,
            ref: bookingRef,
            data: acceptedBooking,
          },
        ],
        corridor: eligibility.corridor,
        anchor: selectSequenceAnchor(activeBookings, eligibility.corridor, booking),
      });
      const candidatePlan = sequencePlan.find((item) => item.id === bookingId);
      const nextSequence = candidatePlan?.poolSequence || sequencePlan.length;
      const nextStatus = "accepted";
      const stopItems = sequencePlan.map((item) =>
        item.id === bookingId
          ? {
              ...item,
              data: {
                ...item.data,
                [BOOKING_FIELDS.status]: nextStatus,
                [BOOKING_FIELDS.operatorUid]: operatorUid,
                [BOOKING_FIELDS.routeDirection]: eligibility.routeDirection,
              },
            }
          : item
      );
      const stopPlan = buildPoolStopPlan({
        items: stopItems,
        corridor: eligibility.corridor,
        previousItems: activeItems,
        routeDirection: eligibility.routeDirection,
      });
      const stopState = poolStopStatePayload(
        stopPlan,
        hasActiveTrip ? "in_progress" : "accepted"
      );

      for (const item of sequencePlan) {
        if (item.id === bookingId) continue;
        const stopIds = bookingStopIdsFromPlan(
          stopState.plannedStops,
          item.id
        );
        const itemStatus = asString(item.data?.[BOOKING_FIELDS.status]);
        const payload = {
          [BOOKING_FIELDS.poolGroupId]: poolGroupId,
          [BOOKING_FIELDS.pooled]: true,
          [BOOKING_FIELDS.poolMax]: POOLING_POLICY.maxConcurrent,
          [BOOKING_FIELDS.poolCriteriaVersion]: POOLING_POLICY.criteriaVersion,
          [BOOKING_FIELDS.routeDirection]: eligibility.routeDirection,
          [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
          [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
          [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
          [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
          [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
          [BOOKING_FIELDS.poolPickupStopId]: stopIds.pickupStopId,
          [BOOKING_FIELDS.poolDropoffStopId]: stopIds.dropoffStopId,
        };
        if (itemStatus !== "on_the_way") {
          payload[BOOKING_FIELDS.poolSequence] = item.poolSequence;
        }
        tx.update(item.ref, payload);
      }

      const candidateStopIds = bookingStopIdsFromPlan(
        stopState.plannedStops,
        bookingId
      );
      tx.update(bookingRef, {
        [BOOKING_FIELDS.status]: nextStatus,
        [BOOKING_FIELDS.operatorUid]: operatorUid,
        [BOOKING_FIELDS.assignedOperatorName]: asString(operatorData.name),
        [BOOKING_FIELDS.assignedOperatorDisplayId]: asString(
          operatorData.operatorId
        ),
        [BOOKING_FIELDS.assignedOperatorPhone]: asString(
          operatorData.phoneNumber
        ),
        [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
        [BOOKING_FIELDS.pooled]: true,
        [BOOKING_FIELDS.poolGroupId]: poolGroupId,
        [BOOKING_FIELDS.poolSequence]: nextSequence,
        [BOOKING_FIELDS.poolCriteriaVersion]: POOLING_POLICY.criteriaVersion,
        [BOOKING_FIELDS.routeDirection]: eligibility.routeDirection,
        ...(routePointsFromBooking(booking).length >= 2
          ? { [BOOKING_FIELDS.routePolyline]: routePointsFromBooking(booking) }
          : {}),
        [BOOKING_FIELDS.poolMax]: POOLING_POLICY.maxConcurrent,
        [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
        [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
        [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
        [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
        [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
        [BOOKING_FIELDS.poolPickupStopId]: candidateStopIds.pickupStopId,
        [BOOKING_FIELDS.poolDropoffStopId]: candidateStopIds.dropoffStopId,
        [BOOKING_FIELDS.poolPhase]: "waiting_pickup",
        [BOOKING_FIELDS.onboard]: false,
        [BOOKING_FIELDS.poolDeferredForOperatorUid]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredRouteDirection]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredPoolGroupId]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredReason]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredUntil]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredAt]: FieldValue.delete(),
        [BOOKING_FIELDS.poolEligibilityScore]: Number(
          eligibility.score.toFixed(3)
        ),
        [BOOKING_FIELDS.poolEtaSnapshot]: {
          addedEtaLimitMinutes: POOLING_POLICY.addedEtaLimitMinutes,
          addedEtaMinutes: Number(eligibility.addedEtaMinutes.toFixed(2)),
          maxPerRiderAddedEtaMinutes: Number(
            eligibility.maxPerRiderAddedEtaMinutes.toFixed(2)
          ),
          maxPerRiderAddedDistanceMeters: Math.round(
            eligibility.maxPerRiderAddedDistanceMeters
          ),
          addedDistanceMeters: Math.round(eligibility.addedDistanceMeters),
          activeDistanceMeters: Math.round(eligibility.activeDistanceMeters),
          pooledDistanceMeters: Math.round(eligibility.pooledDistanceMeters),
          originDeviationMeters: Math.round(
            eligibility.candidateMetrics.originDeviationMeters
          ),
          destinationDeviationMeters: Math.round(
            eligibility.candidateMetrics.destinationDeviationMeters
          ),
          pickupDistanceMeters: Math.round(
            eligibility.pickupDistanceToPoolMeters
          ),
          pickupWindowMinutes: POOLING_POLICY.pickupWindowMinutes,
          maxPickupDistanceMeters: POOLING_POLICY.maxPickupDistanceMeters,
          maxRouteDeviationMeters: POOLING_POLICY.maxRouteDeviationMeters,
          evaluatedAt: nowIso,
        },
      });
      appendStatusHistory({
        tx,
        bookingRef,
        from: "pending",
        to: nextStatus,
        changedBy: operatorUid,
      });

      logger.info("Pooled booking accepted", {
        bookingId,
        operatorUid,
        poolGroupId,
        poolSequence: nextSequence,
        sequenceStrategy: "route_aware_completion_cost",
        eligibilityScore: Number(eligibility.score.toFixed(3)),
        addedEtaMinutes: Number(eligibility.addedEtaMinutes.toFixed(2)),
      });

      return {
        status: nextStatus,
        poolGroupId,
        poolStatus: stopState.poolStatus,
        poolSequence: nextSequence,
        poolMax: POOLING_POLICY.maxConcurrent,
        criteriaVersion: POOLING_POLICY.criteriaVersion,
        sequenceStrategy: "route_aware_completion_cost",
        eligibilityScore: Number(eligibility.score.toFixed(3)),
        addedEtaMinutes: Number(eligibility.addedEtaMinutes.toFixed(2)),
      };
    });
  }
);

/**
 * Rejects a pending pooled booking for the authenticated operator.
 * This remains valid while the operator is mid-trip.
 */
exports.rejectPooledBooking = onCall(
  {
    region: "asia-southeast1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const operatorUid = request.auth.uid;
    const bookingRef = db.collection(COLLECTIONS.bookings).doc(bookingId);
    const onlineOperatorIds = await getOnlineOperatorIds();

    return db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const booking = await hydrateBookingRouteGeometry(
        tx,
        bookingSnap.data() || {}
      );
      const status = asString(booking[BOOKING_FIELDS.status]);
      const assignedOperator =
        asString(booking[BOOKING_FIELDS.operatorUid]) ||
        asString(booking[BOOKING_FIELDS.operatorId]);
      if (status !== "pending" || assignedOperator) {
        throw new HttpsError(
          "failed-precondition",
          "Only unassigned pending bookings can be rejected."
        );
      }

      const rejectedBy = Array.isArray(booking[BOOKING_FIELDS.rejectedBy])
        ? booking[BOOKING_FIELDS.rejectedBy].map(asString).filter(Boolean)
        : [];
      if (rejectedBy.includes(operatorUid)) {
        throw new HttpsError(
          "failed-precondition",
          "You already rejected this booking."
        );
      }

      const updatedRejectedBy = [...new Set([...rejectedBy, operatorUid])];
      const fullyRejected =
        onlineOperatorIds.length > 0 &&
        onlineOperatorIds.every((id) => updatedRejectedBy.includes(id));
      const nextStatus = fullyRejected ? "rejected" : "pending";

      tx.update(bookingRef, {
        [BOOKING_FIELDS.rejectedBy]: updatedRejectedBy,
        [BOOKING_FIELDS.status]: nextStatus,
        [BOOKING_FIELDS.poolDeferredForOperatorUid]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredRouteDirection]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredPoolGroupId]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredReason]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredUntil]: FieldValue.delete(),
        [BOOKING_FIELDS.poolDeferredAt]: FieldValue.delete(),
        [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
      });

      if (nextStatus !== status) {
        appendStatusHistory({
          tx,
          bookingRef,
          from: status,
          to: nextStatus,
          changedBy: operatorUid,
        });
      }

      logger.info("Pooled booking rejected by operator", {
        bookingId,
        operatorUid,
        previousRejectedBy: rejectedBy,
        rejectedBy: updatedRejectedBy,
        nextStatus,
        onlineOperatorIds,
      });

      return {
        status: nextStatus,
        bookingId,
        rejectedBy: updatedRejectedBy,
        fullyRejected,
        message: fullyRejected
          ? "All online operators declined this request; the passenger will see it as rejected."
          : "Booking rejected. It stays pending for other operators.",
      };
    });
  }
);

/**
 * Starts the backend-approved next booking for an operator.
 * This is the server-side gate that guarantees only one on_the_way booking.
 */
exports.startPooledBooking = onCall(
  {
    region: "asia-southeast1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const operatorLat = Number(request.data?.operatorLat);
    const operatorLng = Number(request.data?.operatorLng);
    const hasOperatorLocation = isValidPoint({
      lat: operatorLat,
      lng: operatorLng,
    });
    const operatorUid = request.auth.uid;
    const bookingRef = db.collection(COLLECTIONS.bookings).doc(bookingId);

    return db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const booking = bookingSnap.data() || {};
      if (asString(booking[BOOKING_FIELDS.status]) !== "accepted") {
        throw new HttpsError(
          "failed-precondition",
          "Only an accepted booking can be started."
        );
      }
      if (asString(booking[BOOKING_FIELDS.operatorUid]) !== operatorUid) {
        throw new HttpsError(
          "permission-denied",
          "This booking is assigned to another operator."
        );
      }

      const activeQuery = db
        .collection(COLLECTIONS.bookings)
        .where(BOOKING_FIELDS.operatorUid, "==", operatorUid)
        .where(BOOKING_FIELDS.status, "in", ["accepted", "on_the_way"]);
      const activeSnap = await tx.get(activeQuery);
      const activeDocs = activeSnap.docs;
      const onTheWayDocs = activeDocs.filter(
        (doc) => asString(doc.data()?.[BOOKING_FIELDS.status]) === "on_the_way"
      );
      if (onTheWayDocs.length > 0) {
        throw new HttpsError(
          "failed-precondition",
          "Complete the current active trip before starting the next booking."
        );
      }

      const acceptedItems = activeDocs
        .filter(
          (doc) => asString(doc.data()?.[BOOKING_FIELDS.status]) === "accepted"
        )
        .map((doc) => ({
          id: doc.id,
          ref: doc.ref,
          data: doc.data() || {},
        }));
      const corridor = choosePoolCorridor(
        acceptedItems.map((item) => item.data),
        booking
      );
      if (!corridor) {
        throw new HttpsError(
          "failed-precondition",
          "Unable to determine the pooled route sequence."
        );
      }
      const sequencePlan = planRouteAwarePoolSequence({
        items: acceptedItems,
        corridor,
        anchor: hasOperatorLocation
          ? { lat: operatorLat, lng: operatorLng }
          : selectRouteAnchor([], corridor, booking),
      });
      const stopPlan = buildPoolStopPlan({
        items: sequencePlan,
        corridor,
        previousItems: acceptedItems,
      });
      const stopState = poolStopStatePayload(stopPlan, "in_progress");
      for (const item of sequencePlan) {
        const stopIds = bookingStopIdsFromPlan(
          stopState.plannedStops,
          item.id
        );
        tx.update(item.ref, {
          [BOOKING_FIELDS.poolSequence]: item.poolSequence,
          [BOOKING_FIELDS.poolCriteriaVersion]: POOLING_POLICY.criteriaVersion,
          [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
          [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
          [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
          [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
          [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
          [BOOKING_FIELDS.poolPickupStopId]: stopIds.pickupStopId,
          [BOOKING_FIELDS.poolDropoffStopId]: stopIds.dropoffStopId,
          [BOOKING_FIELDS.poolPhase]:
            item.id === bookingId ? "waiting_pickup" : "waiting_pickup",
        });
      }

      const acceptedIds = new Set(acceptedItems.map((item) => item.id));
      const resolvedStartBookingId =
        startableBookingIdAtCurrentPoolStop(
          stopState.plannedStops,
          acceptedIds
        ) || bookingId;
      const startedItem = sequencePlan.find(
        (item) => item.id === resolvedStartBookingId
      );
      const startedRef = startedItem?.ref || bookingRef;
      const currentStopAllowsBooking = canStartBookingAtCurrentPoolStop(
        stopState.plannedStops,
        resolvedStartBookingId
      );
      if (currentStopAllowsBooking === false) {
        throw new HttpsError(
          "failed-precondition",
          "Start the route at the first pool stop first."
        );
      }
      if (!startedItem) {
        throw new HttpsError(
          "failed-precondition",
          "Unable to resolve the first route stop booking."
        );
      }

      const payload = {
        [BOOKING_FIELDS.status]: "on_the_way",
        [BOOKING_FIELDS.operatorUid]: operatorUid,
        [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
        [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
        [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
        [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
        [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
        [BOOKING_FIELDS.poolPhase]: "waiting_pickup",
        [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
      };
      if (hasOperatorLocation) {
        payload[BOOKING_FIELDS.operatorLat] = operatorLat;
        payload[BOOKING_FIELDS.operatorLng] = operatorLng;
      }

      tx.update(startedRef, payload);
      appendStatusHistory({
        tx,
        bookingRef: startedRef,
        from: "accepted",
        to: "on_the_way",
        changedBy: operatorUid,
      });

      logger.info("Pooled booking started", {
        requestedBookingId: bookingId,
        startedBookingId: resolvedStartBookingId,
        operatorUid,
        currentStopId: stopState.currentStopId,
        currentStopBookingIds:
          currentStopFromPlan(stopState.plannedStops)?.bookingIds || [],
        sequenceOrder: sequencePlan.map((item) => item.id),
        poolGroupId: asString(startedItem.data?.[BOOKING_FIELDS.poolGroupId]),
      });

      return {
        status: "on_the_way",
        bookingId: resolvedStartBookingId,
        requestedBookingId: bookingId,
        startedBookingId: resolvedStartBookingId,
        currentStopId: stopState.currentStopId,
        poolGroupId: asString(startedItem.data?.[BOOKING_FIELDS.poolGroupId]),
      };
    });
  }
);

/**
 * Completes the current backend-approved active booking for an operator.
 */
exports.completePooledBooking = onCall(
  {
    region: "asia-southeast1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const operatorUid = request.auth.uid;
    const bookingRef = db.collection(COLLECTIONS.bookings).doc(bookingId);
    const archiveRef = db.collection(COLLECTIONS.bookingsArchive).doc(bookingId);

    return db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const booking = bookingSnap.data() || {};
      if (asString(booking[BOOKING_FIELDS.status]) !== "on_the_way") {
        throw new HttpsError(
          "failed-precondition",
          "Only the current on-the-way booking can be completed."
        );
      }
      if (asString(booking[BOOKING_FIELDS.operatorUid]) !== operatorUid) {
        throw new HttpsError(
          "permission-denied",
          "This booking is assigned to another operator."
        );
      }

      const activeQuery = db
        .collection(COLLECTIONS.bookings)
        .where(BOOKING_FIELDS.operatorUid, "==", operatorUid)
        .where(BOOKING_FIELDS.status, "==", "on_the_way");
      const activeSnap = await tx.get(activeQuery);
      const activeIds = activeSnap.docs.map((doc) => doc.id);
      if (activeIds.length !== 1 || activeIds[0] !== bookingId) {
        throw new HttpsError(
          "failed-precondition",
          "Complete the backend-approved active booking first."
        );
      }

      const acceptedQuery = db
        .collection(COLLECTIONS.bookings)
        .where(BOOKING_FIELDS.operatorUid, "==", operatorUid)
        .where(BOOKING_FIELDS.status, "==", "accepted");
      const acceptedSnap = await tx.get(acceptedQuery);
      const acceptedItems = acceptedSnap.docs.map((doc) => ({
        id: doc.id,
        ref: doc.ref,
        data: doc.data() || {},
      }));
      if (acceptedItems.length > 0) {
        const corridor = choosePoolCorridor(
          acceptedItems.map((item) => item.data),
          booking
        );
        const bookingEndpoints = getBookingEndpoints(booking);
        if (corridor) {
          const sequencePlan = planRouteAwarePoolSequence({
            items: acceptedItems,
            corridor,
            anchor: bookingEndpoints?.destination || corridor.origin,
          });
          for (const item of sequencePlan) {
            tx.update(item.ref, {
              [BOOKING_FIELDS.poolSequence]: item.poolSequence,
              [BOOKING_FIELDS.poolCriteriaVersion]:
                POOLING_POLICY.criteriaVersion,
            });
          }
        }
      }

      const completedPayload = {
        [BOOKING_FIELDS.status]: "completed",
        [BOOKING_FIELDS.operatorUid]: operatorUid,
        [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
      };

      tx.update(bookingRef, completedPayload);
      appendStatusHistory({
        tx,
        bookingRef,
        from: "on_the_way",
        to: "completed",
        changedBy: operatorUid,
      });
      tx.set(archiveRef, {
        ...booking,
        ...completedPayload,
        bookingId,
        archivedAt: FieldValue.serverTimestamp(),
        archivedStatus: "completed",
      });

      logger.info("Pooled booking completed", {
        bookingId,
        operatorUid,
        poolSequence: Number(booking[BOOKING_FIELDS.poolSequence] || 0),
      });

      return {
        status: "completed",
        bookingId,
      };
    });
  }
);

/**
 * Marks the current backend-approved pool stop as reached.
 *
 * Backward-compatible callable used by the operator app for both pickup and
 * dropoff actions. With the current booking-level backend this maps the first
 * call to "picked up / onboard" and the second call to "completed".
 */
exports.markPoolStopReached = onCall(
  {
    region: "asia-southeast1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in is required.");
    }

    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const operatorLat = Number(request.data?.operatorLat);
    const operatorLng = Number(request.data?.operatorLng);
    const hasOperatorLocation = isValidPoint({
      lat: operatorLat,
      lng: operatorLng,
    });
    const operatorUid = request.auth.uid;
    const bookingRef = db.collection(COLLECTIONS.bookings).doc(bookingId);

    return db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const booking = bookingSnap.data() || {};
      const requestedStatus = asString(booking[BOOKING_FIELDS.status]);
      if (!["accepted", "on_the_way"].includes(requestedStatus)) {
        throw new HttpsError(
          "failed-precondition",
          "Only an active pooled booking can update a pool stop."
        );
      }
      if (asString(booking[BOOKING_FIELDS.operatorUid]) !== operatorUid) {
        throw new HttpsError(
          "permission-denied",
          "This booking is assigned to another operator."
        );
      }

      const poolGroupId = asString(booking[BOOKING_FIELDS.poolGroupId]);
      const poolQuery = poolGroupId
        ? db
            .collection(COLLECTIONS.bookings)
            .where(BOOKING_FIELDS.operatorUid, "==", operatorUid)
            .where(BOOKING_FIELDS.poolGroupId, "==", poolGroupId)
            .where(BOOKING_FIELDS.status, "in", ["accepted", "on_the_way"])
        : db
            .collection(COLLECTIONS.bookings)
            .where(FieldPath.documentId(), "==", bookingId);
      const poolSnap = await tx.get(poolQuery);
      const poolDocs = poolSnap.docs;
      const poolItems = poolDocs.map((doc) => ({
        id: doc.id,
        ref: doc.ref,
        data: doc.data() || {},
      }));
      const poolIds = new Set(poolItems.map((item) => item.id));
      if (!poolIds.has(bookingId)) {
        throw new HttpsError(
          "failed-precondition",
          "This booking is not part of the active pool."
        );
      }
      const hasActivePoolTrip = poolItems.some(
        (item) => asString(item.data?.[BOOKING_FIELDS.status]) === "on_the_way"
      );
      if (!hasActivePoolTrip) {
        throw new HttpsError(
          "failed-precondition",
          "Only an active pooled booking can update a pool stop."
        );
      }

      let stopPlan = Array.isArray(booking[BOOKING_FIELDS.poolStopPlan])
        ? booking[BOOKING_FIELDS.poolStopPlan]
        : [];
      if (stopPlan.length === 0) {
        const corridor = choosePoolCorridor(
          poolItems.map((item) => item.data),
          booking
        );
        if (!corridor) {
          throw new HttpsError(
            "failed-precondition",
            "Unable to determine the current pool stop."
          );
        }
        stopPlan = buildPoolStopPlan({
          items: poolItems,
          corridor,
          previousItems: poolItems,
        });
      }

      const currentStop = currentStopFromPlan(stopPlan);
      if (!currentStop) {
        throw new HttpsError(
          "failed-precondition",
          "There is no active pool stop to complete."
        );
      }
      if (
        hasOperatorLocation &&
        Number.isFinite(Number(currentStop.lat)) &&
        Number.isFinite(Number(currentStop.lng))
      ) {
        const distanceToStopMeters = haversineDistanceMeters(
          { lat: operatorLat, lng: operatorLng },
          { lat: Number(currentStop.lat), lng: Number(currentStop.lng) }
        );
        if (distanceToStopMeters > POOLING_POLICY.stopArrivalRadiusMeters) {
          throw new HttpsError(
            "failed-precondition",
            `Return closer to ${asString(currentStop.stopName || currentStop.jettyName || "the stop")} before completing this stop.`
          );
        }
      }

      const stopBookingIds = Array.isArray(currentStop.bookingIds)
        ? currentStop.bookingIds.map(asString).filter((id) => poolIds.has(id))
        : [];
      if (stopBookingIds.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "The current pool stop has no active bookings."
        );
      }
      const activePoolHandleIds = new Set(
        poolItems
          .filter(
            (item) =>
              asString(item.data?.[BOOKING_FIELDS.status]) === "on_the_way"
          )
          .map((item) => item.id)
      );
      if (
        !canCompleteCurrentPoolStopWithBooking(
          stopPlan,
          bookingId,
          activePoolHandleIds
        )
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Complete the current pool stop first."
        );
      }

      const stopCompletedAt = new Date().toISOString();
      const completedStopPlan = stopPlan.map((stop) =>
        asString(stop.stopId) === asString(currentStop.stopId)
          ? {
              ...stop,
              status: "completed",
              reachedAt: stop.reachedAt || stopCompletedAt,
              completedAt: stopCompletedAt,
            }
          : stop
      );
      const remainingAfterStop = poolItems.filter(
        (item) =>
          !(
            currentStop.stopType === "dropoff" &&
            stopBookingIds.includes(item.id)
          )
      );
      const poolDone = remainingAfterStop.length === 0;
      const stopState = poolStopStatePayload(
        completedStopPlan,
        poolDone ? "completed" : "in_progress"
      );

      const archiveSnaps = new Map();
      if (asString(currentStop.stopType) === "dropoff") {
        for (const stopBookingId of stopBookingIds) {
          const item = poolItems.find((candidate) => candidate.id === stopBookingId);
          if (!item) continue;
          archiveSnaps.set(
            stopBookingId,
            db.collection(COLLECTIONS.bookingsArchive).doc(stopBookingId)
          );
        }
      }

      if (asString(currentStop.stopType) === "pickup") {
        const stopBookingIdSet = new Set(stopBookingIds);
        for (const item of poolItems) {
          const stopIds = bookingStopIdsFromPlan(
            stopState.plannedStops,
            item.id
          );
          const { payload: pickupPayload, isAtStop } =
            buildPickupStopUpdatePayload({
              item,
              stopBookingIds: stopBookingIdSet,
              stopState,
              stopIds,
              hasOperatorLocation,
              operatorLat,
              operatorLng,
            });
          tx.update(item.ref, pickupPayload);
          if (
            isAtStop &&
            asString(item.data?.[BOOKING_FIELDS.status]) === "accepted"
          ) {
            appendStatusHistory({
              tx,
              bookingRef: item.ref,
              from: "accepted",
              to: "on_the_way",
              changedBy: operatorUid,
            });
          }
        }

        logger.info("Pool pickup stop marked reached", {
          bookingIds: stopBookingIds,
          operatorUid,
          stopId: currentStop.stopId,
        });

        return {
          status: "pickup_completed",
          bookingIds: stopBookingIds,
          currentStopId: stopState.currentStopId,
        };
      }

      for (const item of poolItems) {
        const stopIds = bookingStopIdsFromPlan(stopState.plannedStops, item.id);
        const isAtStop = stopBookingIds.includes(item.id);
        const payload = {
          [BOOKING_FIELDS.poolStopPlan]: stopState.plannedStops,
          [BOOKING_FIELDS.currentStopIndex]: stopState.currentStopIndex,
          [BOOKING_FIELDS.currentStopId]: stopState.currentStopId,
          [BOOKING_FIELDS.currentPoolStopId]: stopState.currentStopId,
          [BOOKING_FIELDS.poolStatus]: stopState.poolStatus,
          [BOOKING_FIELDS.poolPickupStopId]: stopIds.pickupStopId,
          [BOOKING_FIELDS.poolDropoffStopId]: stopIds.dropoffStopId,
          [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
        };
        if (hasOperatorLocation) {
          payload[BOOKING_FIELDS.operatorLat] = operatorLat;
          payload[BOOKING_FIELDS.operatorLng] = operatorLng;
        }

        if (!isAtStop) {
          tx.update(item.ref, payload);
          continue;
        }

        const completedPayload = {
          ...payload,
          [BOOKING_FIELDS.status]: "completed",
          [BOOKING_FIELDS.operatorUid]: operatorUid,
          [BOOKING_FIELDS.poolPhase]: "dropped_off",
          [BOOKING_FIELDS.onboard]: false,
          [BOOKING_FIELDS.droppedOffAt]: FieldValue.serverTimestamp(),
        };
        tx.update(item.ref, completedPayload);
        appendStatusHistory({
          tx,
          bookingRef: item.ref,
          from: asString(item.data?.[BOOKING_FIELDS.status]) || "on_the_way",
          to: "completed",
          changedBy: operatorUid,
        });
        const archiveRefForItem = archiveSnaps.get(item.id);
        if (archiveRefForItem) {
          tx.set(archiveRefForItem, {
            ...item.data,
            ...completedPayload,
            bookingId: item.id,
            archivedAt: FieldValue.serverTimestamp(),
            archivedStatus: "completed",
          });
        }
      }

      logger.info("Pool dropoff stop marked reached", {
        bookingIds: stopBookingIds,
        operatorUid,
        stopId: currentStop.stopId,
      });

      return {
        status: poolDone ? "pool_completed" : "dropoff_completed",
        bookingIds: stopBookingIds,
        currentStopId: stopState.currentStopId,
      };
    });
  }
);

/**
 * Replans queued pooled bookings when a booking leaves the active pool through
 * cancellation, release, rejection, or any other non-pooled status transition.
 */
exports.replanPoolSequenceOnBookingExit = onDocumentUpdated(
  {
    document: "bookings/{bookingId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};
    const beforeStatus = asString(before[BOOKING_FIELDS.status]);
    const afterStatus = asString(after[BOOKING_FIELDS.status]);
    const wasInPool =
      beforeStatus === "accepted" || beforeStatus === "on_the_way";
    const isStillInPool =
      afterStatus === "accepted" || afterStatus === "on_the_way";
    const beforeOperatorUid = asString(before[BOOKING_FIELDS.operatorUid]);
    const afterOperatorUid = asString(after[BOOKING_FIELDS.operatorUid]);

    if (!wasInPool) return;
    if (isStillInPool && beforeOperatorUid === afterOperatorUid) return;
    if (!beforeOperatorUid) return;

    await replanRouteAwarePoolForOperator({
      operatorUid: beforeOperatorUid,
      anchorBooking: before,
      reason: `${beforeStatus}_to_${afterStatus || "unassigned"}`,
    });
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
          body: passengerStatusMessage(newStatus, origin, destination),
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
            body: operatorStatusMessage(newStatus, origin, destination),
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

function bookingRouteLabel(origin, destination) {
  const start = origin || "Pickup";
  const end = destination || "Dropoff";
  return `${start} to ${end}`;
}

function passengerStatusMessage(status, origin, destination) {
  const route = bookingRouteLabel(origin, destination);
  switch (status) {
    case "accepted":
      return `Your operator has accepted ${route}.`;
    case "on_the_way":
      return `Your operator is on the way for ${route}.`;
    case "completed":
      return `Your trip from ${route} is complete.`;
    case "cancelled":
      return `Your booking from ${route} was cancelled.`;
    case "rejected":
      return `No operator is available for ${route} right now.`;
    default:
      return `${route}: ${statusLabel(status)}`;
  }
}

function operatorStatusMessage(status, origin, destination) {
  const route = bookingRouteLabel(origin, destination);
  switch (status) {
    case "accepted":
      return `${route} was added to your queue.`;
    case "on_the_way":
      return `${route} is now active.`;
    case "completed":
      return `${route} has been completed.`;
    case "cancelled":
      return `${route} was cancelled by the passenger.`;
    case "rejected":
      return `${route} was declined.`;
    default:
      return `${route}: ${statusLabel(status)}`;
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
 * Rejects unassigned pending bookings when no operators remain online.
 *
 * This prevents passenger requests from waiting indefinitely after the
 * operator supply disappears during dispatch.
 */
exports.rejectStalePendingBookingsWithoutOnlineOperators = onSchedule(
  {
    schedule: "* * * * *",
    timeZone: "Asia/Kuala_Lumpur",
    region: "asia-southeast1",
  },
  async () => {
    await rejectStalePendingBookingsWithoutOnlineOperators();
  }
);

/**
 * Releases accepted pooled bookings that were never started in time.
 *
 * This keeps the backend-owned pool queue from holding stale accepted jobs
 * forever if an operator accepts a request and then abandons the pool.
 */
exports.releaseStaleAcceptedPooledBookings = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Asia/Kuala_Lumpur",
    region: "asia-southeast1",
  },
  async () => {
    const cutoff = new Date(
      Date.now() - POOLING_POLICY.staleAcceptedMinutes * 60 * 1000
    );
    const snapshot = await db
      .collection(COLLECTIONS.bookings)
      .where(BOOKING_FIELDS.status, "==", "accepted")
      .where(BOOKING_FIELDS.pooled, "==", true)
      .where(BOOKING_FIELDS.updatedAt, "<", cutoff)
      .limit(100)
      .get();

    if (snapshot.empty) {
      logger.info("Stale pooled accepted cleanup completed", {
        scanned: 0,
        released: 0,
      });
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      const booking = doc.data() || {};
      const operatorUid = asString(booking[BOOKING_FIELDS.operatorUid]);
      batch.update(doc.ref, {
        [BOOKING_FIELDS.status]: "pending",
        [BOOKING_FIELDS.operatorUid]: null,
        [BOOKING_FIELDS.assignedOperatorName]: FieldValue.delete(),
        [BOOKING_FIELDS.assignedOperatorDisplayId]: FieldValue.delete(),
        [BOOKING_FIELDS.assignedOperatorPhone]: FieldValue.delete(),
        [BOOKING_FIELDS.pooled]: false,
        [BOOKING_FIELDS.poolGroupId]: FieldValue.delete(),
        [BOOKING_FIELDS.poolSequence]: FieldValue.delete(),
        [BOOKING_FIELDS.poolCriteriaVersion]: FieldValue.delete(),
        [BOOKING_FIELDS.poolMax]: FieldValue.delete(),
        [BOOKING_FIELDS.poolEligibilityScore]: FieldValue.delete(),
        [BOOKING_FIELDS.poolEtaSnapshot]: FieldValue.delete(),
        [BOOKING_FIELDS.updatedAt]: FieldValue.serverTimestamp(),
      });
      appendStatusHistory({
        tx: batch,
        bookingRef: doc.ref,
        from: "accepted",
        to: "pending",
        changedBy: operatorUid || "system",
        source: "releaseStaleAcceptedPooledBookings",
      });
    }
    await batch.commit();

    logger.info("Stale pooled accepted cleanup completed", {
      scanned: snapshot.size,
      released: snapshot.size,
      cutoff: cutoff.toISOString(),
      hasMoreEligibleDocs: snapshot.size >= 100,
    });
  }
);

/**
 * Scheduled cleanup for bookings_archive retention.
 *
 * Retention is configured by BOOKING_ARCHIVE_RETENTION_DAYS (default 400).
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
      400
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

/**
 * Automatically archives completed, cancelled, or rejected bookings to the bookings_archive
 * collection if they are not already archived.
 *
 * This provides 100% archiving coverage for all paths including manual, automatic, and system rejections,
 * with zero risk of breaking active dispatch operations or frontends since active records are preserved.
 */
exports.reconcileTerminalBookingToArchive = onDocumentUpdated(
  {
    document: "bookings/{bookingId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;

    const booking = afterSnap.data() || {};
    const bookingId = event.params.bookingId;
    const status = asString(booking[BOOKING_FIELDS.status]);

    const isTerminal = status === "completed" || status === "cancelled" || status === "rejected";
    if (!isTerminal) return;

    // Check if already in bookings_archive
    const archiveRef = db.collection(COLLECTIONS.bookingsArchive).doc(bookingId);
    const archiveSnap = await archiveRef.get();

    if (!archiveSnap.exists) {
      const archivedPayload = {
        ...booking,
        bookingId,
        archivedAt: FieldValue.serverTimestamp(),
        archivedStatus: status,
      };

      await archiveRef.set(archivedPayload);
      logger.info("Automatically reconciled terminal booking to archive", {
        bookingId,
        status,
      });
    }
  }
);

if (process.env.NODE_ENV === "test") {
  module.exports.__poolingTest = {
    BOOKING_FIELDS,
    POOLING_POLICY,
    choosePoolCorridor,
    evaluatePoolingEligibility,
    planRouteAwarePoolSequence,
    buildPoolStopPlan,
    resolveCurrentStopIndex,
    applyCurrentStopState,
    currentStopFromPlan,
    canStartBookingAtCurrentPoolStop,
    startableBookingIdAtCurrentPoolStop,
    canCompleteCurrentPoolStopWithBooking,
    shouldEnforceActivePoolPickupWindow,
  };
  module.exports.__pendingNoOperatorTest = {
    BOOKING_FIELDS,
    PENDING_NO_OPERATOR_POLICY,
    rejectStalePendingBookingsWithoutOnlineOperators,
  };
  module.exports.__drtStabilityTest = {
    BOOKING_FIELDS,
    buildPickupStopUpdatePayload,
  };
}

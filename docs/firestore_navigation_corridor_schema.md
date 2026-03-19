# Firestore Navigation Corridor Schema (Canonical)

This document defines the canonical Firestore schema for River Navigation Phase A.

## Collection

- `navigation_corridors/{corridorId}`

## Canonical Corridor ID

- `melaka_main_01`

## Document Fields

Required fields for `navigation_corridors/melaka_main_01`:

- `corridorId` (string): must equal `melaka_main_01`
- `corridorName` (string): display name for the corridor
- `riverName` (string): river identifier/name
- `isActive` (bool): active corridor flag
- `version` (int): schema/data version, minimum `1`
- `checkpointCount` (int): must equal `14`
- `checkpointOrder` (list<string>): ordered checkpoint IDs from start to end
- `checkpoints` (list<map>): checkpoint metadata list, size `14`
- `polyline` (list<map>): route geometry points (`lat`, `lng`)
- `updatedAt` (timestamp): latest update timestamp

## Checkpoint Sequence Constraint

Canonical `checkpointOrder`:

1. `JETTY_01`
2. `JETTY_02`
3. `JETTY_03`
4. `JETTY_04`
5. `JETTY_05`
6. `JETTY_06`
7. `JETTY_07`
8. `JETTY_08`
9. `JETTY_09`
10. `JETTY_10`
11. `JETTY_11`
12. `JETTY_12`
13. `JETTY_13`
14. `JETTY_14`

## Booking Corridor Linkage Fields

`bookings/{bookingId}` may include corridor metadata to bind trip legs to the canonical route:

- `corridorId` (string)
- `corridorVersion` (int)
- `originCheckpointSeq` (int, 1..14)
- `destinationCheckpointSeq` (int, 1..14)

Constraints:

- If any of the four fields is present, all must be present.
- `corridorId` must equal `melaka_main_01`.
- `originCheckpointSeq < destinationCheckpointSeq`.

## Cross-App Tracking Alignment Notes

- Passenger tracking treats corridor linkage fields as optional metadata.
- Missing or partial corridor linkage fields must not block map rendering, status timeline updates, or cancellation flows.
- When all corridor linkage fields are present, passenger UI may display a lightweight corridor segment hint (`corridorId`, `corridorVersion`, `originCheckpointSeq`, `destinationCheckpointSeq`).
- Operator navigation logic remains authoritative for progression and off-route decisions; passenger app only reflects booking-stream metadata.

## Read-Only Client Policy

Client apps may read `navigation_corridors/*` when authenticated.
Client apps cannot create, update, or delete corridor documents.

## Canonical Example

```json
{
  "corridorId": "melaka_main_01",
  "corridorName": "Sungai Melaka Main Corridor",
  "riverName": "Sungai Melaka",
  "isActive": true,
  "version": 1,
  "checkpointCount": 14,
  "checkpointOrder": [
    "JETTY_01",
    "JETTY_02",
    "JETTY_03",
    "JETTY_04",
    "JETTY_05",
    "JETTY_06",
    "JETTY_07",
    "JETTY_08",
    "JETTY_09",
    "JETTY_10",
    "JETTY_11",
    "JETTY_12",
    "JETTY_13",
    "JETTY_14"
  ],
  "checkpoints": [
    { "checkpointId": "JETTY_01", "seq": 1, "name": "Jetty 1", "lat": 2.2001, "lng": 102.2461 },
    { "checkpointId": "JETTY_02", "seq": 2, "name": "Jetty 2", "lat": 2.2011, "lng": 102.2471 }
  ],
  "polyline": [
    { "lat": 2.2001, "lng": 102.2461 },
    { "lat": 2.2005, "lng": 102.2466 }
  ],
  "updatedAt": "serverTimestamp"
}
```

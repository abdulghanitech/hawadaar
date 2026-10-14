# MirAIe protocol notes

How AirBar talks to MirAIe ACs. Unofficial and observed from the community clients credited in the README, so it may change.

## REST

| Step | Request | Notes |
|---|---|---|
| Sign in | `POST https://auth.miraie.in/simplifi/v1/userManagement/login` | JSON body: `clientId`, `scope`, `password`, and `mobile` (`+91XXXXXXXXXX`) or `email`. Returns `accessToken`, `refreshToken`, `userId`, `expiresIn`. |
| Homes | `GET https://app.miraie.in/simplifi/v1/homeManagement/homes` | Bearer token. `[0].homeId`, and `spaces[].devices[]` with `deviceId`, `deviceName`, `topic[0]`. |
| Status | `GET https://app.miraie.in/simplifi/v1/deviceManagement/devices/{deviceId}/mobile/status` | Same fields as the MQTT status message, plus `onlineStatus`. |

## MQTT

- Broker `mqtt.miraie.in:8883`, TLS, MQTT 3.1.1.
- Username: `homeId`. Password: the access token. An expired token is refused with CONNACK code 4 or 5; sign in again and reconnect.
- Subscribe to `{topic}/status` (state changes) and `{topic}/connectionStatus` (`onlineStatus: "true"/"false"`).
- Publish commands to `{topic}/control`.

## Commands

Every command is `{"ki": 1, "cnt": "an", "sid": "1"}` plus the fields to change:

| Field | Meaning | Values |
|---|---|---|
| `ps` | Power | `"on"`, `"off"` |
| `actmp` | Setpoint (°C) | `"16"` … `"30"`, as a string |
| `acmd` | Mode | `cool`, `auto`, `dry`, `fan`, `heat` |
| `acfs` | Fan speed | `auto`, `quiet`, `low`, `medium`, `high` |
| `acvs` | Vertical louver | `0` = swing, `1` (level) … `5` (down), as a number |
| `achs` | Horizontal louver | `0` = swing, `1` … `5` (model dependent) |
| `acem` | Eco | `"on"`, `"off"`; the MirAIe app also sets `actmp: "26"` and `acpm: "off"` |
| `acpm` | Powerful | `"on"`, `"off"` |
| `acdc` | Display light | `"on"`, `"off"` |
| `cnv` | Converti capacity | `0`, `40` … `110` (Converti models) |

## Status-only fields

| Field | Meaning |
|---|---|
| `rmtmp` | Room temperature. From firmware 3.02 (`V`) it's packed as `"<fraction × 256>.<degrees>"`, e.g. `"43.28"` = 28 + 43/256 ≈ 28.17 °C. |
| `rssi` | The AC's own Wi-Fi signal, dBm. |
| `V` | Wi-Fi module firmware version. |
| `lcmd` | The last field changed, e.g. `acfs`. |
| `cnt` | Source of the last change: `an` (app), `rem` (remote), `auto`. |
| `acsp` | Probably sleep profile (`"none"`); not yet confirmed. |

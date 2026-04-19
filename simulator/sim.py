"""
Universal Telemetry Simulator  –  v2.0
Simulates realistic physics for CAR, TRAIN, and PLANE missions.

Usage:
    python simulator.py [--server http://localhost:8080]

Environment variables:
    ORS_API_KEY   –  OpenRouteService API key (or edit CONFIG below)
    SERVER_URL    –  Override server URL
"""

import os
import sys
import math
import time
import random
import logging
import argparse
import requests
from dataclasses import dataclass, field
from typing import List, Dict, Optional

# ── Configuration ─────────────────────────────────────────────────────────────
CONFIG = {
    "SERVER_URL":  os.getenv("SERVER_URL", "http://localhost:8080"),
    "ORS_API_KEY": os.getenv("ORS_API_KEY",
        "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImVlNmNlOGU1ZjQ2YjRlMTk4YjQyNmJiOGE5OWZjOTYxIiwiaCI6Im11cm11cjY0In0="),
    "POLL_INTERVAL_S":    2.0,
    "FRAME_INTERVAL_S":   1.0,   # seconds between telemetry frames
    "REQUEST_TIMEOUT_S":  5,
    "MAX_ROUTE_POINTS":   80,
}

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s.%(msecs)03d  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("simulator")

# ── Vehicle profiles ──────────────────────────────────────────────────────────
@dataclass
class VehicleProfile:
    name:            str
    max_speed_kmh:   float   # cruise speed
    accel_kmh_s:     float   # ramp-up per second
    decel_kmh_s:     float   # brake per second
    cruise_alt_m:    float   # cruising altitude (0 = ground)
    climb_rate_ms:   float   # m/s climb (planes)
    base_temp_c:     float   # idle engine temp
    temp_per_kmh:    float   # °C gained per km/h of speed
    max_temp_warn:   float   # temp at which warning fires
    bat_drain_pct_s: float   # battery % lost per second
    speed_noise:     float   # random ±noise on cruise speed


PROFILES: Dict[str, VehicleProfile] = {
    "CAR": VehicleProfile(
        name="CAR", max_speed_kmh=130, accel_kmh_s=12, decel_kmh_s=18,
        cruise_alt_m=0, climb_rate_ms=0, base_temp_c=70, temp_per_kmh=0.18,
        max_temp_warn=108, bat_drain_pct_s=0.004, speed_noise=6,
    ),
    "TRAIN": VehicleProfile(
        name="TRAIN", max_speed_kmh=300, accel_kmh_s=8, decel_kmh_s=12,
        cruise_alt_m=0, climb_rate_ms=0, base_temp_c=65, temp_per_kmh=0.10,
        max_temp_warn=120, bat_drain_pct_s=0.006, speed_noise=4,
    ),
    "PLANE": VehicleProfile(
        name="PLANE", max_speed_kmh=870, accel_kmh_s=25, decel_kmh_s=35,
        cruise_alt_m=10_500, climb_rate_ms=12, base_temp_c=55, temp_per_kmh=0.07,
        max_temp_warn=150, bat_drain_pct_s=0.002, speed_noise=10,
    ),
}

# ── Geo utilities ─────────────────────────────────────────────────────────────
def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371.0
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lon2 - lon1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


def bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """True bearing from point 1 to point 2, in degrees [0-360]."""
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dλ = math.radians(lon2 - lon1)
    x = math.sin(dλ) * math.cos(φ2)
    y = math.cos(φ1) * math.sin(φ2) - math.sin(φ1) * math.cos(φ2) * math.cos(dλ)
    return (math.degrees(math.atan2(x, y)) + 360) % 360

# ── Route fetching ────────────────────────────────────────────────────────────
def geocode(city: str) -> Optional[List[float]]:
    """Return [lon, lat] for a city name via ORS Geocoding."""
    url = (
        "https://api.openrouteservice.org/geocode/search"
        f"?api_key={CONFIG['ORS_API_KEY']}&text={city}&size=1"
    )
    r = requests.get(url, timeout=CONFIG["REQUEST_TIMEOUT_S"])
    r.raise_for_status()
    features = r.json().get("features", [])
    if not features:
        raise ValueError(f"City not found: {city!r}")
    return features[0]["geometry"]["coordinates"]   # [lon, lat]


def great_circle_route(start: List[float], end: List[float], n: int = 60) -> List[Dict]:
    """Linearly interpolate n waypoints (geodesic approx) for air routes."""
    pts = []
    for i in range(n):
        t = i / (n - 1)
        lon = start[0] + (end[0] - start[0]) * t
        lat = start[1] + (end[1] - start[1]) * t
        pts.append({"lat": lat, "lon": lon})
    return pts


def get_route(origin: str, destination: str, vehicle_type: str) -> List[Dict]:
    log.info("Geocoding %r and %r…", origin, destination)
    start = geocode(origin)
    end   = geocode(destination)

    if vehicle_type == "PLANE":
        log.info("Using great-circle interpolation for PLANE route.")
        return great_circle_route(start, end, n=CONFIG["MAX_ROUTE_POINTS"])

    profile = "driving-car"   # same road network for CAR and TRAIN (approximation)
    log.info("Fetching road route from ORS (profile=%s)…", profile)

    url = (
        f"https://api.openrouteservice.org/v2/directions/{profile}"
        f"?api_key={CONFIG['ORS_API_KEY']}"
        f"&start={start[0]},{start[1]}&end={end[0]},{end[1]}"
    )
    r = requests.get(url, timeout=CONFIG["REQUEST_TIMEOUT_S"])
    r.raise_for_status()
    all_pts = r.json()["features"][0]["geometry"]["coordinates"]

    # Downsample to ~MAX_ROUTE_POINTS waypoints
    step = max(1, len(all_pts) // CONFIG["MAX_ROUTE_POINTS"])
    sampled = [{"lat": p[1], "lon": p[0]} for p in all_pts[::step]]
    # Always include the last point
    if sampled[-1] != {"lat": all_pts[-1][1], "lon": all_pts[-1][0]}:
        sampled.append({"lat": all_pts[-1][1], "lon": all_pts[-1][0]})
    log.info("Route ready: %d waypoints.", len(sampled))
    return sampled

# ── Physics engine ────────────────────────────────────────────────────────────
@dataclass
class PhysicsState:
    speed:      float = 0.0    # km/h
    altitude:   float = 0.0    # m
    engine_temp: float = 0.0   # °C  (set from profile on init)
    battery:    float = 100.0  # %
    warning:    bool  = False
    heading:    float = 0.0    # degrees


def update_physics(
    ps: PhysicsState,
    profile: VehicleProfile,
    target_speed: float,
    dt: float,
    total_points: int,
    point_idx: int,
) -> PhysicsState:

    # ── Speed ──────────────────────────────────────────────────────────────
    diff = target_speed - ps.speed
    if diff > 0:
        ps.speed = min(ps.speed + profile.accel_kmh_s * dt, target_speed)
    else:
        ps.speed = max(ps.speed + diff * 0.4, target_speed)   # softer braking

    # Small cruise noise
    if abs(ps.speed - target_speed) < 2:
        ps.speed += random.uniform(-profile.speed_noise * 0.5,
                                    profile.speed_noise * 0.5)
        ps.speed = max(0, ps.speed)

    # ── Altitude (plane only) ──────────────────────────────────────────────
    if profile.cruise_alt_m > 0:
        climb_phase   = total_points * 0.15
        descent_phase = total_points * 0.85

        if point_idx < climb_phase:
            target_alt = profile.cruise_alt_m * (point_idx / climb_phase)
        elif point_idx > descent_phase:
            frac = (point_idx - descent_phase) / (total_points - descent_phase)
            target_alt = profile.cruise_alt_m * (1 - frac)
        else:
            target_alt = profile.cruise_alt_m

        alt_diff = target_alt - ps.altitude
        ps.altitude += max(-profile.climb_rate_ms * dt * 2,
                           min(profile.climb_rate_ms * dt, alt_diff))
        ps.altitude = max(0, ps.altitude)
    else:
        # Ground vehicles: slight terrain noise
        ps.altitude += random.uniform(-1.5, 1.5)
        ps.altitude = max(0, ps.altitude)

    # ── Engine temp ────────────────────────────────────────────────────────
    target_temp  = profile.base_temp_c + ps.speed * profile.temp_per_kmh
    target_temp += random.uniform(-1, 1)
    ps.engine_temp += (target_temp - ps.engine_temp) * 0.05   # thermal lag

    # ── Battery ────────────────────────────────────────────────────────────
    speed_factor = max(0.2, ps.speed / profile.max_speed_kmh)
    ps.battery  -= profile.bat_drain_pct_s * speed_factor * dt
    ps.battery   = max(0, ps.battery)

    # ── Warning ────────────────────────────────────────────────────────────
    ps.warning = ps.engine_temp > profile.max_temp_warn or ps.battery < 12.0

    return ps


# ── Transmission ──────────────────────────────────────────────────────────────
def send_telemetry(server: str, payload: dict) -> bool:
    try:
        r = requests.post(
            f"{server}/api/telemetry",
            json=payload,
            timeout=CONFIG["REQUEST_TIMEOUT_S"],
        )
        return r.status_code == 200
    except requests.RequestException as e:
        log.warning("TX error: %s", e)
        return False


def mark_mission_running(server: str, mission: dict) -> None:
    m = dict(mission)
    m["status"] = "RUNNING"
    try:
        requests.post(f"{server}/api/mission", json=m,
                      timeout=CONFIG["REQUEST_TIMEOUT_S"])
    except requests.RequestException:
        pass


# ── Mission runner ────────────────────────────────────────────────────────────
def run_mission(server: str, mission: dict) -> None:
    origin      = mission.get("origin",       "Milano")
    destination = mission.get("destination",  "Roma")
    v_type      = mission.get("vehicle_type", "CAR").upper()

    profile = PROFILES.get(v_type, PROFILES["CAR"])
    log.info("=" * 56)
    log.info("MISSION START  %s → %s  [%s]", origin, destination, profile.name)
    log.info("=" * 56)

    # Fetch route with fallback
    try:
        route = get_route(origin, destination, v_type)
    except Exception as e:
        log.error("Route fetch failed: %s — using fallback straight line.", e)
        route = great_circle_route([9.19, 45.46], [12.49, 41.90], n=40)

    mark_mission_running(server, mission)

    n        = len(route)
    ps       = PhysicsState(engine_temp=profile.base_temp_c, altitude=0.0)
    dt       = CONFIG["FRAME_INTERVAL_S"]
    v_id     = f"{profile.name}-001"

    for idx, pt in enumerate(route):
        # Target speed: ramp up, cruise, ramp down in last 15 %
        decel_start = int(n * 0.82)
        if idx > decel_start:
            progress   = (idx - decel_start) / (n - decel_start)
            target_spd = profile.max_speed_kmh * max(0.05, 1 - progress)
        else:
            target_spd = profile.max_speed_kmh

        # Compute heading toward next waypoint
        if idx < n - 1:
            nxt = route[idx + 1]
            ps.heading = bearing_deg(pt["lat"], pt["lon"], nxt["lat"], nxt["lon"])

        ps = update_physics(ps, profile, target_spd, dt, n, idx)

        payload = {
            "vehicle_id": v_id,
            "physics": {
                "speed_kmh":    round(ps.speed, 2),
                "heading":      round(ps.heading, 1),
                "acceleration": round((target_spd - ps.speed) / dt, 3),
            },
            "gps": {
                "latitude":  round(pt["lat"],    6),
                "longitude": round(pt["lon"],    6),
                "altitude":  round(ps.altitude,  1),
            },
            "system_status": {
                "engine_temp":   round(ps.engine_temp, 1),
                "battery_level": round(ps.battery,     1),
                "warning_light": ps.warning,
            },
        }

        ok = send_telemetry(server, payload)
        status_sym = "✓" if ok else "✗"
        warn_sym   = " ⚠ WARNING" if ps.warning else ""

        log.info(
            "[%2d/%d] %s  %.4f,%.4f  | %.0f km/h  alt=%.0f m"
            "  T=%.1f°C  bat=%.0f%%%s",
            idx + 1, n, status_sym,
            pt["lat"], pt["lon"],
            ps.speed, ps.altitude,
            ps.engine_temp, ps.battery,
            warn_sym,
        )

        time.sleep(dt)

    log.info("MISSION COMPLETE  ✓  frames sent: %d", n)
    log.info("=" * 56)


# ── Main polling loop ─────────────────────────────────────────────────────────
def main(server: str) -> None:
    log.info("Simulator v2.0 — connecting to %s", server)
    log.info("Polling for mission every %.1f s…", CONFIG["POLL_INTERVAL_S"])

    while True:
        try:
            r = requests.get(f"{server}/api/mission",
                             timeout=CONFIG["REQUEST_TIMEOUT_S"])
            if r.status_code == 200:
                mission = r.json()
                if mission.get("status") == "PENDING":
                    run_mission(server, mission)
        except requests.RequestException as e:
            log.debug("Poll error (server down?): %s", e)
        except KeyboardInterrupt:
            log.info("Simulator stopped by user.")
            sys.exit(0)

        time.sleep(CONFIG["POLL_INTERVAL_S"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Universal Telemetry Simulator")
    parser.add_argument("--server", default=CONFIG["SERVER_URL"],
                        help="Backend server URL (default: %(default)s)")
    args = parser.parse_args()
    main(args.server)

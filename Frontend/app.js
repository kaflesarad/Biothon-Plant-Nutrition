const NEPAL_CENTER = [28.394, 84.124];
const NEPAL_BOUNDS = [[26.35, 80.05], [30.45, 88.20]];

const KATHMANDU = { lat: 27.7172, lng: 85.3240 };

let map;
let userMarker;
let latestLiveData = {
  temperature: 24,
  humidity: 65,
  moisture: 50,
};
let latestGeoData = {
  altitude: 1400,
  region: "Hill",
  climateZone: "Subtropical_Humid",
};

function getApiBase() {
  if (window.location.origin.startsWith("http")) {
    return window.location.origin;
  }
  return "http://127.0.0.1:8000";
}

const API_BASE = getApiBase();

function initMap() {
  map = L.map("map", {
    center: NEPAL_CENTER,
    zoom: 7,
    zoomControl: false,
    attributionControl: false,
  });

  L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
    attribution:
      '© <a href="https://carto.com/">CARTO</a> | © <a href="https://www.openstreetmap.org/copyright">OSM</a>',
    subdomains: "abcd",
    maxZoom: 19,
  }).addTo(map);

  L.control.zoom({ position: "topright" }).addTo(map);
  L.control.attribution({ position: "bottomright", prefix: false }).addTo(map);

  map.fitBounds(NEPAL_BOUNDS, { padding: [20, 20] });

  map.on("move", () => {
    const c = map.getCenter();
    document.getElementById("map-coords").textContent = `${c.lat.toFixed(4)}° N, ${c.lng.toFixed(4)}° E`;
  });
}

function setLocationText(msg) {
  document.getElementById("location-text").textContent = msg;
}

function inferRegionFromAltitude(altitude) {
  if (altitude == null || Number.isNaN(altitude)) {
    return "Hill";
  }
  if (altitude >= 2200) {
    return "Mountain";
  }
  if (altitude >= 700) {
    return "Hill";
  }
  return "Terai";
}

function inferClimateZoneFromContext(altitude, temperature, humidity, month) {
  const isMonsoon = month >= 6 && month <= 9;

  if (altitude >= 3400 || temperature <= 6) {
    return "Alpine_Cold";
  }
  if (altitude >= 2200) {
    return "Cool_Mountain";
  }
  if (altitude >= 1100) {
    return "Temperate_Hill";
  }
  if (isMonsoon && humidity >= 65) {
    return "Tropical_Monsoon";
  }
  return "Subtropical_Humid";
}

function climateDisplayLabel(zone) {
  return zone.replaceAll("_", " ");
}

function addUserMarker(lat, lng) {
  if (userMarker) {
    map.removeLayer(userMarker);
  }

  const pinSvg = `
    <svg xmlns="http://www.w3.org/2000/svg" width="28" height="40" viewBox="0 0 28 40">
      <defs>
        <filter id="ds" x="-20%" y="-10%" width="140%" height="130%">
          <feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#000" flood-opacity="0.35"/>
        </filter>
      </defs>
      <path d="M14 0C6.27 0 0 6.27 0 14c0 10.5 14 26 14 26s14-15.5 14-26C28 6.27 21.73 0 14 0z"
            fill="#EA4335" filter="url(#ds)"/>
      <circle cx="14" cy="14" r="6" fill="#B72D25"/>
      <circle cx="14" cy="14" r="4" fill="#fff"/>
    </svg>`;

  const icon = L.divIcon({
    className: "red-pin-wrapper",
    html: pinSvg,
    iconSize: [28, 40],
    iconAnchor: [14, 40],
    popupAnchor: [0, -36],
  });

  userMarker = L.marker([lat, lng], { icon }).addTo(map).bindPopup("<strong>📍 You are here</strong>").openPopup();
}

async function reverseGeocode(lat, lng) {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=10&addressdetails=1`;
    const res = await fetch(url, { headers: { "Accept-Language": "en" } });
    const data = await res.json();

    let placeName = "Nepal";
    if (data.address) {
      const parts = [];
      if (data.address.city || data.address.town || data.address.village) {
        parts.push(data.address.city || data.address.town || data.address.village);
      }
      if (data.address.state) {
        parts.push(data.address.state);
      }
      if (data.address.country) {
        parts.push(data.address.country);
      }
      placeName = parts.join(", ") || data.display_name || "Nepal";
    }

    document.getElementById("user-region").textContent = placeName;
    setLocationText(placeName);
  } catch {
    const fallback = `${lat.toFixed(3)}°N, ${lng.toFixed(3)}°E`;
    document.getElementById("user-region").textContent = fallback;
    setLocationText(fallback);
  }
}

function getTempClass(t) {
  if (t >= 35) return "hot";
  if (t >= 25) return "warm";
  if (t >= 15) return "mild";
  return "cool";
}

function getWeatherDescription(temp, cloud, precip) {
  if (precip > 2) return "🌧️ Rainy conditions";
  if (precip > 0) return "🌦️ Light precipitation";
  if (cloud > 80) return "☁️ Overcast skies";
  if (cloud > 50) return "⛅ Partly cloudy";
  if (temp > 30) return "☀️ Hot and sunny";
  if (temp > 20) return "🌤️ Clear and pleasant";
  if (temp > 10) return "🌥️ Cool and mild";
  return "❄️ Cold conditions";
}

function getWindDirection(deg) {
  const dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
  return `${dirs[Math.round(deg / 22.5) % 16]} (${deg}°)`;
}

function safeSetText(id, value) {
  const el = document.getElementById(id);
  if (el) {
    el.textContent = value;
  }
}

function syncAdvisorInputsWithLiveData() {
  document.getElementById("input-temp").value = latestLiveData.temperature.toFixed(1);
  document.getElementById("input-humidity").value = latestLiveData.humidity.toFixed(1);
  document.getElementById("input-moisture").value = latestLiveData.moisture.toFixed(1);
}

function refreshClimateZoneFromInputs() {
  const month = Number(document.getElementById("input-month").value || new Date().getMonth() + 1);
  latestGeoData.climateZone = inferClimateZoneFromContext(
    latestGeoData.altitude,
    latestLiveData.temperature,
    latestLiveData.humidity,
    month
  );
  safeSetText("user-climate", climateDisplayLabel(latestGeoData.climateZone));
}

async function fetchSeasonalCrops(region, month) {
  const el = document.getElementById("seasonal-crops");
  if (!el) return;
  el.textContent = 'Loading...';
  try {
    const params = new URLSearchParams();
    if (region) params.append('region', region);
    if (month) params.append('month', String(month));
    let res = await fetch(`${API_BASE}/api/seasonal-crops?${params.toString()}`);
    if (!res.ok) {
      // try alternate underscore path
      res = await fetch(`${API_BASE}/api/seasonal_crops?${params.toString()}`);
    }
    if (!res.ok) {
      // try root-level JSON fallback
      res = await fetch(`${API_BASE}/seasonal-crops.json?${params.toString()}`);
    }
    if (!res.ok) throw new Error('server error');
    const data = await res.json();
    renderSeasonalCrops(data);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(err);
    el.textContent = 'Unavailable';
  }
}

function renderSeasonalCrops(data) {
  const el = document.getElementById('seasonal-crops');
  if (!el) return;
  if (!data || !data.in_season_crops || data.in_season_crops.length === 0) {
    el.innerHTML = '<em>No in-season crops found</em>';
    return;
  }
  el.innerHTML = '<ul>' + data.in_season_crops.map(c => `<li>${c}</li>`).join('') + '</ul>';
}

async function fetchWeather(lat, lng) {
  const loading = document.getElementById("weather-loading");
  const content = document.getElementById("weather-content");

  try {
    const params = new URLSearchParams({
      latitude: lat,
      longitude: lng,
      current:
        "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,cloud_cover,wind_speed_10m,wind_direction_10m",
      daily: "uv_index_max,et0_fao_evapotranspiration,sunrise,sunset",
      hourly: "soil_moisture_0_to_1cm",
      timezone: "auto",
      forecast_days: 1,
    });

    const res = await fetch(`https://api.open-meteo.com/v1/forecast?${params}`);
    const data = await res.json();
    if (!data.current) {
      throw new Error("No weather data from API");
    }

    const c = data.current;
    const d = data.daily;

    const temp = Math.round(c.temperature_2m);
    const tempEl = document.getElementById("temp-value");
    tempEl.textContent = temp;
    tempEl.className = `ws-temp-val ${getTempClass(temp)}`;

    safeSetText("temp-desc", getWeatherDescription(temp, c.cloud_cover, c.precipitation));
    safeSetText("feels-like", `${Math.round(c.apparent_temperature)}°C`);

    const humidity = Number(c.relative_humidity_2m);
    safeSetText("humidity-value", `${humidity}%`);
    setTimeout(() => {
      document.getElementById("humidity-bar").style.width = `${humidity}%`;
    }, 300);

    safeSetText("wind-speed", `${c.wind_speed_10m} km/h`);
    safeSetText("wind-dir", getWindDirection(c.wind_direction_10m));
    safeSetText("cloud-cover", `${c.cloud_cover}%`);
    safeSetText("precipitation", `${c.precipitation} mm`);

    const now = new Date();
    safeSetText(
      "weather-time",
      `${now.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" })} · ${now.toLocaleTimeString("en-US", {
        hour: "2-digit",
        minute: "2-digit",
      })}`
    );

    let moisturePct = latestLiveData.moisture;
    if (data.hourly?.soil_moisture_0_to_1cm) {
      const m = data.hourly.soil_moisture_0_to_1cm[0];
      if (m != null) {
        moisturePct = Number((m * 100).toFixed(1));
        safeSetText("soil-moisture", `${moisturePct.toFixed(1)}%`);
      } else {
        safeSetText("soil-moisture", "N/A");
      }
    }

    if (d) {
      safeSetText("soil-et", d.et0_fao_evapotranspiration?.[0] != null ? `${d.et0_fao_evapotranspiration[0]} mm` : "N/A");

      const uv = d.uv_index_max?.[0];
      const uvEl = document.getElementById("soil-uv");
      if (uv != null) {
        uvEl.textContent = uv.toFixed(1);
        uvEl.className = `side-val ${uv > 8 ? "danger" : uv > 5 ? "warn" : "good"}`;
      }

      if (d.sunrise?.[0] && d.sunset?.[0]) {
        const hrs = ((new Date(d.sunset[0]) - new Date(d.sunrise[0])) / 3600000).toFixed(1);
        safeSetText("soil-daylight", `${hrs} hrs`);
      }
    }

    latestLiveData = {
      temperature: Number(c.temperature_2m),
      humidity: Number(humidity),
      moisture: Number(moisturePct),
    };

    refreshClimateZoneFromInputs();

    syncAdvisorInputsWithLiveData();

    loading.style.display = "none";
    content.style.display = "flex";
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(err);
    loading.innerHTML = '<div class="error-state">⚠️ Could not load weather data.</div>';
  }
}

function initializeFormDefaults() {
  const now = new Date();
  document.getElementById("input-month").value = now.getMonth() + 1;
  document.getElementById("input-ph").value = "6.2";
  syncAdvisorInputsWithLiveData();
  refreshClimateZoneFromInputs();
  // refresh seasonal crops widget for current region/month
  const monthVal = Number(document.getElementById('input-month')?.value) || (new Date().getMonth() + 1);
  fetchSeasonalCrops(latestGeoData.region, monthVal);
}

function setAiStatus(text, level = "neutral") {
  const status = document.getElementById("ai-status");
  status.textContent = text;
  status.className = `advisor-status ${level}`;
}

function renderRecommendation(result) {
  document.getElementById("ai-result").style.display = "block";

  safeSetText("result-crop", result.best_crop);
  safeSetText("result-confidence", `${result.confidence_pct.toFixed(2)}%`);
  safeSetText("result-n", `${result.nutrient_recommendation.N_kg_per_ha.toFixed(2)}`);
  safeSetText("result-p", `${result.nutrient_recommendation.P_kg_per_ha.toFixed(2)}`);
  safeSetText("result-k", `${result.nutrient_recommendation.K_kg_per_ha.toFixed(2)}`);

  const topText = result.top_3
    .map((item) => `${item.crop} (${item.score_pct.toFixed(2)}%)`)
    .join(", ");
  safeSetText("result-top3", `Top 3 crops: ${topText}`);
  safeSetText("result-advice", result.advisory);
}

async function runAiRecommendation() {
  const payload = {
    region: document.getElementById("input-region").value,
    month: Number(document.getElementById("input-month").value),
    pH: Number(document.getElementById("input-ph").value),
    moisture: Number(document.getElementById("input-moisture").value),
    temperature: Number(document.getElementById("input-temp").value),
    humidity: Number(document.getElementById("input-humidity").value),
    altitude_m: latestGeoData.altitude,
    climate_zone: latestGeoData.climateZone,
  };

  setAiStatus("Running AI recommendation...", "pending");

  try {
    const response = await fetch(`${API_BASE}/api/recommend`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Unknown API error");
    }

    renderRecommendation(data);
    if (data.geo_context) {
      setAiStatus(
        `Recommendation ready for ${data.geo_context.region} / ${climateDisplayLabel(data.geo_context.climate_zone)} @ ${data.geo_context.altitude_m}m.`,
        "ok"
      );
    } else {
      setAiStatus("Recommendation ready.", "ok");
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(err);
    setAiStatus(`AI service error: ${err.message}`, "error");
  }
}

async function fetchModelInfo() {
  try {
    const res = await fetch(`${API_BASE}/api/model-info`);
    const data = await res.json();

    const chip = document.getElementById("pitch-chip");
    if (!data.model_exists) {
      chip.textContent = "Model not ready";
      chip.classList.add("warn-chip");
      return;
    }

    const accuracy = data.metrics?.crop_accuracy;
    if (typeof accuracy === "number") {
      chip.textContent = `Model accuracy: ${(accuracy * 100).toFixed(2)}%`;
    } else {
      chip.textContent = "Model ready";
    }
  } catch {
    const chip = document.getElementById("pitch-chip");
    chip.textContent = "Model info unavailable";
    chip.classList.add("warn-chip");
  }
}

function applyUserLocation(lat, lng, altitude, regionLabel) {
  safeSetText("user-lat", `${lat.toFixed(5)}°`);
  safeSetText("user-lng", `${lng.toFixed(5)}°`);
  safeSetText("user-alt", altitude != null ? `${Math.round(altitude)} m` : "N/A");

  const inferredRegion = inferRegionFromAltitude(altitude);
  document.getElementById("input-region").value = inferredRegion;
  latestGeoData.altitude = altitude != null && !Number.isNaN(altitude) ? Number(altitude) : 1400;
  latestGeoData.region = inferredRegion;

  if (regionLabel) {
    safeSetText("user-region", `${regionLabel} (${inferredRegion})`);
  }

  refreshClimateZoneFromInputs();
}

function getUserLocation() {
  if (!navigator.geolocation) {
    setLocationText("Geolocation not supported");
    applyUserLocation(KATHMANDU.lat, KATHMANDU.lng, null, "Kathmandu");
    addUserMarker(KATHMANDU.lat, KATHMANDU.lng);
    fetchWeather(KATHMANDU.lat, KATHMANDU.lng);
    return;
  }

  navigator.geolocation.getCurrentPosition(
    async (pos) => {
      const lat = pos.coords.latitude;
      const lng = pos.coords.longitude;
      const alt = pos.coords.altitude;

      document.getElementById("location-chip").classList.add("active");

      addUserMarker(lat, lng);
      map.flyTo([lat, lng], 11, { duration: 2 });

      await reverseGeocode(lat, lng);
      const regionLabel = document.getElementById("user-region").textContent;
      applyUserLocation(lat, lng, alt, regionLabel);

      fetchWeather(lat, lng);
    },
    () => {
      setLocationText("Kathmandu, Nepal (default)");
      applyUserLocation(KATHMANDU.lat, KATHMANDU.lng, null, "Kathmandu");
      addUserMarker(KATHMANDU.lat, KATHMANDU.lng);
      fetchWeather(KATHMANDU.lat, KATHMANDU.lng);
    },
    { enableHighAccuracy: true, timeout: 10000 }
  );
}

function bindAdvisorActions() {
  document.getElementById("input-region").addEventListener("change", (event) => {
    latestGeoData.region = event.target.value;
    const monthVal = Number(document.getElementById('input-month')?.value) || (new Date().getMonth() + 1);
    fetchSeasonalCrops(latestGeoData.region, monthVal);
  });

  document.getElementById("input-month").addEventListener("change", () => {
    refreshClimateZoneFromInputs();
    const monthVal = Number(document.getElementById('input-month')?.value) || (new Date().getMonth() + 1);
    fetchSeasonalCrops(latestGeoData.region, monthVal);
  });

  document.getElementById("use-live-btn").addEventListener("click", () => {
    syncAdvisorInputsWithLiveData();

    refreshClimateZoneFromInputs();

    setAiStatus("Live weather values loaded into AI form.", "ok");
  });

  document.getElementById("run-ai-btn").addEventListener("click", runAiRecommendation);
}

document.addEventListener("DOMContentLoaded", () => {
  initMap();
  initializeFormDefaults();
  bindAdvisorActions();
  fetchModelInfo();
  getUserLocation();
});

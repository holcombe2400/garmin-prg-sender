const PRG_MAGIC = [0xd0, 0x00, 0xd0];
const PRG_TYPE = 255;
const PRG_SUBTYPE = 17;
const MAX_EXPECTED_PRG_SIZE = 10 * 1024 * 1024;
const LARGE_PRG_WARNING_SIZE = 4 * 1024 * 1024;
const SAFE_GFDI_PACKET_SIZE = 375;
const MAX_EXPERIMENTAL_GFDI_PACKET_SIZE = 8192;
const LARGE_GFDI_PACKET_SIZE = 1500;
const SAFE_BLE_FRAGMENT_SIZE = 20;
const MAX_BLE_FRAGMENT_SIZE = 180;
const MAX_PIPELINE_WINDOW = 16;
const TRUSTED_DEVICE_KEY = "garminPrgSender.trustedDevice";
const SAVED_PRG_DB_NAME = "garminPrgSender.savedPrgs";
const SAVED_PRG_DB_VERSION = 1;
const SAVED_PRG_STORE = "files";
const MAX_SAVED_PRGS = 12;
const GITHUB_REPO_KEY = "garminPrgSender.githubRepo";
const DEFAULT_GITHUB_REPO = "holcombe2400/garmin-vpet";
const TUNING_HISTORY_KEY = "garminPrgSender.tuningHistory";
const MAX_TUNING_HISTORY = 20;
const FAST_FENIX6_TUNING = Object.freeze({
  maxPacketSize: 400,
  fragmentSize: SAFE_BLE_FRAGMENT_SIZE,
  pipelineWindow: 2,
  writeDelayMs: 0,
  label: "fenix 6 fast preset"
});
const FAST_FENIX6_MLR_TUNING = Object.freeze({
  maxPacketSize: 1500,
  fragmentSize: SAFE_BLE_FRAGMENT_SIZE,
  pipelineWindow: 8,
  writeDelayMs: 0,
  label: "fenix 6 MLR fast preset"
});
const BENCHMARK_MIN_BYTES = 12 * 1024;
const BENCHMARK_MAX_BYTES = 24 * 1024;
const BENCHMARK_PROFILE_TIMEOUT_MS = 18000;
const GFDI_WRITE_TIMEOUT_MS = 10000;
const MAX_BENCHMARK_RESTARTS = 6;
const WIFI_PROBE_TIMEOUT_MS = 3500;
const WIFI_MAX_PORTS = 12;
const MLR_FLAG_MASK = 0x80;
const MLR_HANDLE_MASK = 0x70;
const MLR_REQ_NUM_MASK = 0x0f;
const MLR_SEQ_NUM_MASK = 0x3f;
const MLR_MAX_SEQ_NUM = 0x3f;
const MLR_INITIAL_MAX_UNACKED_SEND = 16;
const MLR_ACK_TIMEOUT_MS = 250;
const MLR_ACK_TRIGGER_THRESHOLD = 5;
const MLR_INITIAL_RETRANSMISSION_TIMEOUT_MS = 1000;
const MLR_MAX_RETRANSMISSION_TIMEOUT_MS = 20000;
const MLR_SEND_WINDOW_TIMEOUT_MS = 8000;

const GADGETBRIDGE_CLIENT_ID = 2;
const REQUEST_REGISTER_ML = 0;
const REQUEST_REGISTER_ML_RESP = 1;
const REQUEST_CLOSE_ALL = 5;
const REQUEST_CLOSE_ALL_RESP = 6;
const SERVICE_GFDI = 1;

const UUIDS = {
  v2Service: "6a4e2800-667b-11e3-949a-0800200c9a66",
  v1Service: "6a4e2401-667b-11e3-949a-0800200c9a66",
  v1Receive: "6a4ecd28-667b-11e3-949a-0800200c9a66",
  v1Send: "6a4e4c80-667b-11e3-949a-0800200c9a66",
  v0Service: "9b012401-bc30-ce9a-e111-0f67e491abde",
  v0Receive: "4acbcd28-7425-868e-f447-915c8f00d0cb",
  v0Send: "df334c80-e6a7-d082-274d-78fc66f85e16",
  deviceInformation: "0000180a-0000-1000-8000-00805f9b34fb",
  observedFenix6: "72daa6c3-29c2-6283-0c4a-2818e4d37e75",
  observedGarmin1: "3e1d50cd-7e3e-427d-8e1c-b78aa87fe624",
  observedGarmin2: "daf56201-0000-1000-8000-00805f9b34fb"
};

const GarminMessage = {
  RESPONSE: 5000,
  UPLOAD_REQUEST: 5003,
  FILE_TRANSFER_DATA: 5004,
  CREATE_FILE: 5005,
  SYSTEM_EVENT: 5030
};

const Status = {
  ACK: 0
};

const CreateStatus = {
  OK: 0,
  DUPLICATE: 1,
  NO_SPACE: 2,
  UNSUPPORTED: 3,
  NO_SLOTS: 4,
  NO_SPACE_FOR_TYPE: 5
};

const UploadStatus = {
  OK: 0
};

const TransferStatus = {
  OK: 0,
  RESEND: 1,
  CRC_MISMATCH: 3,
  OFFSET_MISMATCH: 4,
  SYNC_PAUSED: 5
};

const SystemEvent = {
  SYNC_COMPLETE: 0,
  SYNC_READY: 8
};

const CRC_CONSTANTS = [
  0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401,
  0xa001, 0x6c00, 0x7800, 0xb401, 0x5000, 0x9c01, 0x8801, 0x4400
];

const fileInput = document.querySelector("#fileInput");
const fileMeta = document.querySelector("#fileMeta");
const githubRepoInput = document.querySelector("#githubRepoInput");
const githubPrgInput = document.querySelector("#githubPrgInput");
const refreshGithubPrgsButton = document.querySelector("#refreshGithubPrgsButton");
const loadGithubPrgButton = document.querySelector("#loadGithubPrgButton");
const githubPrgMeta = document.querySelector("#githubPrgMeta");
const savedPrgInput = document.querySelector("#savedPrgInput");
const loadSavedPrgButton = document.querySelector("#loadSavedPrgButton");
const deleteSavedPrgButton = document.querySelector("#deleteSavedPrgButton");
const savedPrgMeta = document.querySelector("#savedPrgMeta");
const chooseWatchButton = document.querySelector("#chooseWatchButton");
const connectButton = document.querySelector("#connectButton");
const sendButton = document.querySelector("#sendButton");
const bleState = document.querySelector("#bleState");
const watchMeta = document.querySelector("#watchMeta");
const watchIdentity = document.querySelector("#watchIdentity");
const deviceIdText = document.querySelector("#deviceIdText");
const transportText = document.querySelector("#transportText");
const confirmTargetInput = document.querySelector("#confirmTargetInput");
const trustedWatchText = document.querySelector("#trustedWatchText");
const rememberWatchButton = document.querySelector("#rememberWatchButton");
const clearWatchButton = document.querySelector("#clearWatchButton");
const autoTuneButton = document.querySelector("#autoTuneButton");
const benchmarkSendButton = document.querySelector("#benchmarkSendButton");
const retryButton = document.querySelector("#retryButton");
const stopUploadButton = document.querySelector("#stopUploadButton");
const riskyPipelineInput = document.querySelector("#riskyPipelineInput");
const reliableMlrInput = document.querySelector("#reliableMlrInput");
const progressBar = document.querySelector("#progressBar");
const progressText = document.querySelector("#progressText");
const statusText = document.querySelector("#statusText");
const logEl = document.querySelector("#log");
const detailsButton = document.querySelector("#detailsButton");
const packetSizeInput = document.querySelector("#packetSizeInput");
const fragmentSizeInput = document.querySelector("#fragmentSizeInput");
const pipelineWindowInput = document.querySelector("#pipelineWindowInput");
const writeDelayInput = document.querySelector("#writeDelayInput");
const keepAwakeInput = document.querySelector("#keepAwakeInput");
const foregroundWarning = document.querySelector("#foregroundWarning");
const apiModeInput = document.querySelector("#apiModeInput");
const pickerModeInput = document.querySelector("#pickerModeInput");
const serviceModeInput = document.querySelector("#serviceModeInput");
const bridgeDiagnosticsText = document.querySelector("#bridgeDiagnosticsText");
const bridgeDiagnosticsButton = document.querySelector("#bridgeDiagnosticsButton");
const scanButton = document.querySelector("#scanButton");
const stopScanButton = document.querySelector("#stopScanButton");
const scanSummary = document.querySelector("#scanSummary");
const wifiIpInput = document.querySelector("#wifiIpInput");
const wifiPortsInput = document.querySelector("#wifiPortsInput");
const wifiProbeButton = document.querySelector("#wifiProbeButton");
const wifiStopButton = document.querySelector("#wifiStopButton");
const wifiProbeSummary = document.querySelector("#wifiProbeSummary");

let selectedFile = null;
let selectedDevice = null;
let connection = null;
let isBusy = false;
let isScanning = false;
let targetConfirmed = false;
let trustedDevice = loadTrustedDevice();
let activeScan = null;
let scanTimer = null;
let scanAdvertisementHandler = null;
let scanAdvertisementCount = 0;
let scanDevices = new Map();
let savedPrgRecords = [];
let githubPrgAssets = [];
let isUploading = false;
let wakeLock = null;
let lastUploadRequest = null;
let retryAvailable = false;
let uploadAbortController = null;
let isWifiProbing = false;
let wifiProbeAbortController = null;

init().catch((error) => showError("Startup failed", error));

async function init() {
  applyRuntimeDefaults();
  detailsButton.addEventListener("click", () => {
    logEl.hidden = !logEl.hidden;
    detailsButton.textContent = logEl.hidden ? "Show Details" : "Hide Details";
  });
  fileInput.addEventListener("change", onFileSelected);
  githubRepoInput.value = loadGithubRepoSetting();
  githubRepoInput.addEventListener("change", () => {
    try {
      const repo = normalizeGitHubRepo(githubRepoInput.value);
      githubRepoInput.value = repo;
      saveGithubRepoSetting(repo);
      updateGithubPrgMeta();
    } catch (error) {
      githubPrgMeta.textContent = messageOf(error);
    }
  });
  githubPrgInput.addEventListener("change", () => {
    updateGithubPrgMeta();
    updateButtons();
  });
  refreshGithubPrgsButton.addEventListener("click", refreshGithubPrgs);
  loadGithubPrgButton.addEventListener("click", loadGithubPrg);
  savedPrgInput.addEventListener("change", () => {
    updateSavedPrgMeta();
    updateButtons();
  });
  loadSavedPrgButton.addEventListener("click", loadSavedPrg);
  deleteSavedPrgButton.addEventListener("click", deleteSavedPrg);
  apiModeInput.addEventListener("change", () => {
    log(`Bluetooth API mode changed to ${apiModeInput.value}. ${bluetoothApiStatusText()}`);
    updateBridgeDiagnostics();
    refreshBleAvailability();
    updateButtons();
  });
  serviceModeInput.addEventListener("change", () => {
    log(`Access mode changed to ${serviceModeLabel(serviceModeInput.value)}.`);
    updateBridgeDiagnostics();
  });
  bridgeDiagnosticsButton?.addEventListener("click", () => logBridgeDiagnostics("Manual bridge diagnostics"));
  chooseWatchButton.addEventListener("click", chooseWatch);
  connectButton.addEventListener("click", connectWatch);
  scanButton.addEventListener("click", runDiagnosticScan);
  stopScanButton.addEventListener("click", () => stopDiagnosticScan("Scan stopped."));
  wifiProbeButton?.addEventListener("click", runWifiProbe);
  wifiStopButton?.addEventListener("click", stopWifiProbe);
  rememberWatchButton.addEventListener("click", rememberSelectedWatch);
  clearWatchButton.addEventListener("click", clearTrustedWatch);
  autoTuneButton?.addEventListener("click", autoTuneSettings);
  benchmarkSendButton?.addEventListener("click", () => sendPrg({ benchmark: true }));
  retryButton?.addEventListener("click", retryLastUpload);
  stopUploadButton?.addEventListener("click", () => stopActiveUpload("Upload stopped by user."));
  reliableMlrInput?.addEventListener("change", onReliableMlrChanged);
  confirmTargetInput.addEventListener("change", () => {
    targetConfirmed = confirmTargetInput.checked;
    if (targetConfirmed && selectedDevice) {
      log(`Confirmed target watch: ${deviceLabel(selectedDevice)}`);
      setStatus("Target watch confirmed.");
    } else {
      setStatus("Target watch confirmation cleared.");
    }
    updateButtons();
  });
  keepAwakeInput.addEventListener("change", () => {
    if (keepAwakeInput.checked) {
      requestWakeLock("manual toggle").catch((error) => log(`Keep-awake request failed: ${messageOf(error)}`));
    } else {
      releaseWakeLock();
    }
  });
  sendButton.addEventListener("click", () => sendPrg({ benchmark: false }));
  updateTrustedWatchUi();
  await refreshSavedPrgLibrary();
  updateBridgeDiagnostics();
  logBridgeDiagnostics("Startup bridge diagnostics");
  window.setTimeout(updateBridgeDiagnostics, 500);
  window.setTimeout(updateBridgeDiagnostics, 1500);
  window.addEventListener("focus", updateBridgeDiagnostics);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden && isUploading) {
      foregroundWarning.textContent = "Upload was interrupted because Bluefy left the foreground. Reopen Bluefy and restart the upload.";
      log("Page left foreground during upload; iOS may suspend Web Bluetooth and interrupt the transfer.");
    }
    if (!document.hidden) {
      updateBridgeDiagnostics();
      if (isUploading) {
        requestWakeLock("return to foreground").catch((error) => log(`Keep-awake request failed after foreground return: ${messageOf(error)}`));
      }
    }
  });
  await refreshBleAvailability();
  updateButtons();
}

function applyRuntimeDefaults() {
  const userAgent = navigator.userAgent || "";
  const hasWebble = Boolean(navigator.webble || navigator.beacio);
  const looksLikeSafari = /safari/i.test(userAgent) && !/chrome|crios|fxios|edgios|android/i.test(userAgent);
  if (looksLikeSafari && hasWebble) {
    apiModeInput.value = "webble-first";
  } else {
    apiModeInput.value = "bluetooth-only";
  }
  pickerModeInput.value = "name";
  serviceModeInput.value = "transport";
}

async function refreshBleAvailability() {
  const bluetooth = getBluetooth();
  if (!bluetooth) {
    setBleState("no webble", false);
    setStatus(`iOSWebBLE/Web Bluetooth is not available in this browser. ${bluetoothApiStatusText()}`);
    return;
  }
  if (typeof bluetooth.getAvailability === "function") {
    const available = await bluetooth.getAvailability();
    setBleState(available ? "webble ready" : "bluetooth off", available);
    return;
  }
  setBleState("webble ready", true);
}

async function onFileSelected() {
  selectedFile = null;
  const file = fileInput.files?.[0];
  if (!file) {
    fileMeta.textContent = "No file selected";
    updateButtons();
    return;
  }
  try {
    const data = new Uint8Array(await file.arrayBuffer());
    validatePrg(data);
    selectedFile = { name: file.name, size: data.length, data };
    fileMeta.textContent = selectedPrgMetaText(file.name, data.length);
    await savePrgToLibrary(file.name, data, file.lastModified || Date.now());
    setStatus("PRG loaded and saved locally.");
    log(`Selected PRG: ${file.name} (${data.length} bytes)`);
    logLargePrgWarning(file.name, data.length);
  } catch (error) {
    fileInput.value = "";
    fileMeta.textContent = "No file selected";
    showError("Invalid PRG", error);
  }
  updateButtons();
}

async function refreshSavedPrgLibrary(selectedId = savedPrgInput?.value || "") {
  if (!savedPrgInput) return;
  if (!supportsSavedPrgLibrary()) {
    savedPrgRecords = [];
    savedPrgInput.innerHTML = '<option value="">Saved PRGs unavailable</option>';
    savedPrgInput.disabled = true;
    savedPrgMeta.textContent = "This browser does not support local saved PRGs.";
    updateButtons();
    return;
  }

  try {
    const records = await getAllSavedPrgs();
    savedPrgRecords = records.sort((left, right) => String(right.savedAt).localeCompare(String(left.savedAt)));
    savedPrgInput.replaceChildren();
    if (!savedPrgRecords.length) {
      savedPrgInput.append(new Option("No saved PRGs", ""));
      savedPrgInput.disabled = true;
    } else {
      savedPrgInput.disabled = false;
      for (const record of savedPrgRecords) {
        savedPrgInput.append(new Option(`${record.name} (${formatBytes(record.size)})`, record.id));
      }
      savedPrgInput.value = savedPrgRecords.some((record) => record.id === selectedId) ? selectedId : savedPrgRecords[0].id;
    }
    updateSavedPrgMeta();
  } catch (error) {
    savedPrgRecords = [];
    savedPrgInput.innerHTML = '<option value="">Saved PRGs error</option>';
    savedPrgInput.disabled = true;
    savedPrgMeta.textContent = `Saved PRGs unavailable: ${messageOf(error)}`;
    log(`Saved PRG refresh failed: ${messageOf(error)}`);
  }
  updateButtons();
}

function updateSavedPrgMeta() {
  const record = selectedSavedPrgRecord();
  if (!record) {
    savedPrgMeta.textContent = "Choose a PRG once to save it locally on this device.";
    return;
  }
  const savedDate = record.savedAt ? new Date(record.savedAt).toLocaleString() : "unknown time";
  savedPrgMeta.textContent = `Saved locally: ${record.name} - ${formatBytes(record.size)} - ${savedDate}`;
}

async function savePrgToLibrary(name, data, lastModified) {
  if (!supportsSavedPrgLibrary()) {
    savedPrgMeta.textContent = "Local saved PRGs are not available in this browser.";
    return;
  }
  try {
    const id = savedPrgId(name, data.length);
    const record = {
      id,
      name,
      size: data.length,
      lastModified,
      savedAt: new Date().toISOString(),
      data: data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)
    };
    await putSavedPrg(record);
    await trimSavedPrgLibrary();
    await refreshSavedPrgLibrary(id);
    log(`Saved PRG locally: ${name} (${data.length} bytes)`);
  } catch (error) {
    savedPrgMeta.textContent = `Could not save PRG locally: ${messageOf(error)}`;
    log(`Could not save PRG locally: ${messageOf(error)}`);
  }
}

async function loadSavedPrg() {
  const selectedId = savedPrgInput.value;
  if (!selectedId) return;
  try {
    setBusy(true);
    const record = await getSavedPrg(selectedId);
    if (!record) throw new Error("Saved PRG was not found.");
    const data = savedRecordToBytes(record);
    validatePrg(data);
    selectedFile = { name: record.name, size: data.length, data };
    fileInput.value = "";
    fileMeta.textContent = selectedPrgMetaText(record.name, data.length, "saved");
    setStatus("Saved PRG loaded.");
    log(`Loaded saved PRG: ${record.name} (${data.length} bytes)`);
    logLargePrgWarning(record.name, data.length);
  } catch (error) {
    showError("Load saved PRG failed", error);
  } finally {
    setBusy(false);
  }
}

async function deleteSavedPrg() {
  const selectedId = savedPrgInput.value;
  const record = selectedSavedPrgRecord();
  if (!selectedId || !record) return;
  try {
    setBusy(true);
    await deleteSavedPrgRecord(selectedId);
    if (selectedFile?.name === record.name && selectedFile?.size === record.size) {
      selectedFile = null;
      fileMeta.textContent = "No file selected";
    }
    setStatus("Saved PRG deleted.");
    log(`Deleted saved PRG: ${record.name}`);
    await refreshSavedPrgLibrary();
  } catch (error) {
    showError("Delete saved PRG failed", error);
  } finally {
    setBusy(false);
  }
}

async function refreshGithubPrgs() {
  try {
    setBusy(true);
    const repo = normalizeGitHubRepo(githubRepoInput.value);
    githubRepoInput.value = repo;
    saveGithubRepoSetting(repo);
    githubPrgMeta.textContent = "Fetching GitHub Releases...";
    githubPrgInput.replaceChildren(new Option("Fetching...", ""));
    githubPrgInput.disabled = true;
    githubPrgAssets = [];
    updateButtons();

    const releases = await fetchGithubReleases(repo);
    githubPrgAssets = releases
      .flatMap((release) => (release.assets || [])
        .filter((asset) => /\.prg$/i.test(asset.name || ""))
        .map((asset) => ({
          id: String(asset.id),
          name: asset.name,
          size: asset.size || 0,
          downloadUrl: asset.browser_download_url,
          apiUrl: asset.url,
          release: release.name || release.tag_name,
          tag: release.tag_name,
          prerelease: Boolean(release.prerelease),
          publishedAt: release.published_at || release.created_at || ""
        })));

    githubPrgInput.replaceChildren();
    if (!githubPrgAssets.length) {
      githubPrgInput.append(new Option("No .prg release assets found", ""));
      githubPrgInput.disabled = true;
      githubPrgMeta.textContent = `No .prg assets found in recent releases for ${repo}.`;
    } else {
      githubPrgInput.disabled = false;
      for (const asset of githubPrgAssets) {
        const releaseLabel = asset.prerelease ? `${asset.release} prerelease` : asset.release;
        githubPrgInput.append(new Option(`${asset.name} (${formatBytes(asset.size)}) - ${releaseLabel}`, asset.id));
      }
      updateGithubPrgMeta();
    }
    log(`Fetched ${githubPrgAssets.length} GitHub PRG asset(s) from ${repo}.`);
  } catch (error) {
    githubPrgAssets = [];
    githubPrgInput.replaceChildren(new Option("GitHub fetch failed", ""));
    githubPrgInput.disabled = true;
    githubPrgMeta.textContent = `GitHub fetch failed: ${messageOf(error)}`;
    showError("GitHub fetch failed", error);
  } finally {
    setBusy(false);
  }
}

async function loadGithubPrg() {
  const asset = selectedGithubPrgAsset();
  if (!asset) return;
  try {
    setBusy(true);
    setStatus(`Downloading ${asset.name}...`);
    githubPrgMeta.textContent = `Downloading ${asset.name}...`;
    const data = await downloadGithubPrg(asset);
    validatePrg(data);
    selectedFile = { name: asset.name, size: data.length, data };
    fileInput.value = "";
    fileMeta.textContent = selectedPrgMetaText(asset.name, data.length, "GitHub");
    await savePrgToLibrary(asset.name, data, Date.parse(asset.publishedAt) || Date.now());
    setStatus("GitHub PRG loaded and saved locally.");
    githubPrgMeta.textContent = `Loaded ${asset.name} from ${asset.release}.`;
    log(`Loaded GitHub PRG: ${asset.name} (${data.length} bytes) from ${asset.release}`);
    logLargePrgWarning(asset.name, data.length);
  } catch (error) {
    showError("GitHub PRG load failed", error);
    githubPrgMeta.textContent = `GitHub PRG load failed: ${messageOf(error)}`;
  } finally {
    setBusy(false);
  }
}

async function fetchGithubReleases(repo) {
  const response = await fetch(`https://api.github.com/repos/${repo}/releases?per_page=20`, {
    headers: { Accept: "application/vnd.github+json" }
  });
  if (!response.ok) {
    throw new Error(`GitHub releases returned ${response.status} ${response.statusText}`);
  }
  return await response.json();
}

async function downloadGithubPrg(asset) {
  let firstError = null;
  try {
    return await fetchPrgBytes(asset.downloadUrl);
  } catch (error) {
    firstError = error;
    log(`Direct GitHub asset download failed: ${messageOf(error)}`);
  }
  try {
    return await fetchPrgBytes(asset.apiUrl, { Accept: "application/octet-stream" });
  } catch (error) {
    throw new Error(`Could not download GitHub PRG. ${firstError ? `${messageOf(firstError)}; ` : ""}${messageOf(error)}`);
  }
}

async function fetchPrgBytes(url, headers = {}) {
  const response = await fetch(url, { headers });
  if (!response.ok) {
    throw new Error(`download returned ${response.status} ${response.statusText}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

function updateGithubPrgMeta() {
  const asset = selectedGithubPrgAsset();
  if (!asset) {
    const repo = githubRepoInput?.value || DEFAULT_GITHUB_REPO;
    githubPrgMeta.textContent = `Fetch public .prg release assets from ${repo}.`;
    return;
  }
  const date = asset.publishedAt ? new Date(asset.publishedAt).toLocaleString() : "unknown date";
  githubPrgMeta.textContent = `${asset.release} - ${asset.name} - ${formatBytes(asset.size)} - ${date}`;
}

async function chooseWatch() {
  try {
    setBusy(true);
    const pickerMode = pickerModeInput.value;
    updateBridgeDiagnostics();
    log(`Bluetooth API mode: ${apiModeInput.value}. ${bluetoothApiStatusText()}`);
    logBridgeDiagnostics("Pre-picker bridge diagnostics");
    log(`Opening WebBLE device chooser (${pickerMode} mode).`);
    selectedDevice = await requestBluetoothDeviceWithFallback(pickerMode);
    connection = null;
    setTargetConfirmed(false);
    selectedDevice.addEventListener?.("gattserverdisconnected", () => {
      connection = null;
      setTargetConfirmed(false);
      updateWatchIdentity("Disconnected");
      updateTrustedWatchUi();
      log("Watch disconnected.");
      setStatus("Watch disconnected.");
      updateButtons();
    });
    updateWatchIdentity("Not connected");
    updateTrustedWatchUi();
    setStatus("Watch selected.");
    log(`Selected watch: ${deviceLabel(selectedDevice)} using ${serviceModeLabel(serviceModeInput.value)}.`);
    if (serviceModeInput.value === "grant") {
      log("Grant-only selection succeeded. If Connect fails with service access denied, choose the watch again with GFDI v2 only.");
      setStatus("Watch selected with grant-only access. Try Connect; service access may be limited.");
    }
  } catch (error) {
    if (isOriginPickerRejection(error)) {
      log("iOSWebBLE rejected the chosen device as not offered to this page origin.");
      logBridgeDiagnostics("Origin rejection bridge diagnostics");
    }
    showError("Watch selection failed", error);
  } finally {
    setBusy(false);
  }
}

async function requestBluetoothDeviceWithFallback(pickerMode) {
  const candidates = getBluetoothCandidates();
  if (!candidates.length) throw new Error("iOSWebBLE/Web Bluetooth is not available.");

  const candidate = candidates[0];
  const variant = buildRequestVariant(pickerMode);
  try {
    log(`Trying ${candidate.label} requestDevice directly (${variant.label}).`);
    return await candidate.bluetooth.requestDevice(variant.options);
  } catch (error) {
    log(`${candidate.label} requestDevice directly (${variant.label}) failed: ${messageOf(error)}`);
    if (isOriginPickerRejection(error)) {
      const foundLateCandidate = await appendLateBluetoothCandidates(candidates);
      if (foundLateCandidate && apiModeInput.value !== "webble-only") {
        apiModeInput.value = "webble-only";
        updateBridgeDiagnostics();
        await refreshBleAvailability();
        updateButtons();
        log("Switched Bluetooth API to iOSWebBLE only. Tap Choose Watch again.");
        throw new Error("WebBLE is now active. Tap Choose Watch again; this first tap only woke the bridge.");
      }
      updateBridgeDiagnostics();
      const nextMode = nextPickerMode(pickerMode);
      if (nextMode) {
        pickerModeInput.value = nextMode;
        log(`Switched picker mode to ${pickerModeLabel(nextMode)}. Tap Choose Watch again.`);
        throw new Error(`Picker handoff failed. Switched picker mode to ${pickerModeLabel(nextMode)}; tap Choose Watch again.`);
      }
      const nextService = nextServiceMode(serviceModeInput.value);
      if (nextService) {
        serviceModeInput.value = nextService;
        pickerModeInput.value = "name";
        updateBridgeDiagnostics();
        log(`Switched access mode to ${serviceModeLabel(nextService)} and reset picker mode to Name filter. Tap Choose Watch again.`);
        throw new Error(`Picker handoff failed. Switched access mode to ${serviceModeLabel(nextService)}; tap Choose Watch again.`);
      }
    }
    throw error;
  }
}

function buildRequestVariant(pickerMode) {
  const serviceMode = serviceModeInput?.value || "transport";
  return {
    label: `${pickerMode} picker, ${serviceModeLabel(serviceMode)}`,
    matchMode: pickerMode,
    options: buildDeviceRequestOptions(pickerMode, serviceMode)
  };
}

function nextPickerMode(mode) {
  if (mode === "name") return "garmin";
  if (mode === "garmin") return "broad";
  return null;
}

function pickerModeLabel(mode) {
  if (mode === "name") return "Name filter";
  if (mode === "garmin") return "Garmin filter";
  if (mode === "broad") return "Broad picker";
  return mode;
}

function nextServiceMode(mode) {
  if (mode === "transport") return "v2";
  if (mode === "v2") return "grant";
  if (mode === "full") return "transport";
  return null;
}

function serviceModeLabel(mode) {
  if (mode === "transport") return "Garmin transport services";
  if (mode === "v2") return "GFDI v2 only";
  if (mode === "grant") return "grant-only/no optional services";
  if (mode === "full") return "full diagnostics services";
  return mode;
}

async function getExistingDevice(candidate, pickerMode) {
  const referringDevice = candidate.bluetooth.referringDevice;
  if (referringDevice && deviceMatchesPicker(referringDevice, pickerMode)) {
    log(`Using ${candidate.label}.referringDevice: ${deviceLabel(referringDevice)}`);
    return referringDevice;
  }
  if (typeof candidate.bluetooth.getDevices !== "function") return null;
  try {
    const devices = await candidate.bluetooth.getDevices();
    log(`${candidate.label}.getDevices returned ${devices.length} device(s).`);
    for (const device of devices) {
      log(`Permitted device: ${deviceLabel(device)}`);
    }
    const matched = pickPermittedDevice(devices, pickerMode);
    if (matched) {
      log(`Using permitted device: ${deviceLabel(matched)}`);
      return matched;
    }
  } catch (error) {
    log(`${candidate.label}.getDevices failed: ${messageOf(error)}`);
  }
  return null;
}

function pickPermittedDevice(devices, pickerMode) {
  const exact = devices.find((device) => (device.name || "").toLowerCase() === "fenix 6 pro");
  if (exact) return exact;
  if (pickerMode === "name") return devices.find((device) => deviceMatchesPicker(device, pickerMode)) || null;
  const garminDevices = devices.filter((device) => deviceMatchesPicker(device, pickerMode));
  return garminDevices.length === 1 ? garminDevices[0] : null;
}

function deviceMatchesPicker(device, pickerMode) {
  const name = (device?.name || "").toLowerCase();
  if (pickerMode === "broad") return true;
  if (pickerMode === "name") return name === "fenix 6 pro" || name.startsWith("fenix 6") || name.startsWith("fenix");
  return name.includes("garmin") || name.includes("fenix");
}

async function runDiagnosticScan() {
  if (isScanning) return;
  const bluetooth = requireBluetooth();
  updateBridgeDiagnostics();
  log(`Bluetooth API mode: ${apiModeInput.value}. ${bluetoothApiStatusText()}`);
  logBridgeDiagnostics("Pre-scan bridge diagnostics");
  if (typeof bluetooth.requestLEScan !== "function") {
    setStatus("Diagnostic scanning is not available in this WebBLE runtime.");
    log("navigator.bluetooth.requestLEScan is not available.");
    return;
  }

  scanAdvertisementCount = 0;
  scanDevices = new Map();
  scanSummary.textContent = "Scanning...";
  setScanning(true);

  scanAdvertisementHandler = (event) => {
    scanAdvertisementCount += 1;
    const item = describeAdvertisement(event);
    scanDevices.set(item.id, item);
    scanSummary.textContent = `${scanDevices.size} device(s), ${scanAdvertisementCount} advertisement(s)`;
    log(formatAdvertisement(item));
  };

  bluetooth.addEventListener("advertisementreceived", scanAdvertisementHandler);
  try {
    try {
      log("Starting 20s all-advertisements scan.");
      activeScan = await bluetooth.requestLEScan({
        acceptAllAdvertisements: true,
        keepRepeatedDevices: true
      });
    } catch (error) {
      log(`All-advertisements scan failed: ${messageOf(error)}`);
      log("Retrying 20s Garmin-filtered scan.");
      activeScan = await bluetooth.requestLEScan({
        filters: buildDiagnosticScanFilters(),
        keepRepeatedDevices: true
      });
    }
    scanTimer = window.setTimeout(() => stopDiagnosticScan("Scan complete."), 20000);
    setStatus("Scanning BLE advertisements for 20 seconds.");
  } catch (error) {
    stopDiagnosticScan("Scan failed.", false);
    if (isHandleMessageError(error)) {
      log("This iOSWebBLE runtime appears to expose requestLEScan incompletely; use Choose Watch instead of Scan 20s.");
    }
    showError("Diagnostic scan failed", error);
  }
}

function stopDiagnosticScan(message = "Scan complete.", shouldLog = true) {
  const bluetooth = getBluetooth();
  if (scanTimer) {
    window.clearTimeout(scanTimer);
    scanTimer = null;
  }
  if (activeScan && typeof activeScan.stop === "function") {
    try {
      activeScan.stop();
    } catch (error) {
      log(`Scan stop failed: ${messageOf(error)}`);
    }
  }
  activeScan = null;
  if (scanAdvertisementHandler && bluetooth?.removeEventListener) {
    bluetooth.removeEventListener("advertisementreceived", scanAdvertisementHandler);
  }
  scanAdvertisementHandler = null;
  setScanning(false);
  scanSummary.textContent = `${scanDevices.size} device(s), ${scanAdvertisementCount} advertisement(s)`;
  setStatus(`${message} Saw ${scanDevices.size} device(s).`);
  if (shouldLog) {
    log(`${message} Saw ${scanDevices.size} device(s), ${scanAdvertisementCount} advertisement(s).`);
  }
}

async function runWifiProbe() {
  if (isWifiProbing || isBusy || isScanning) return;
  const ip = normalizeWifiIp(wifiIpInput?.value || "");
  if (!ip) {
    wifiProbeSummary.textContent = "Enter a valid IPv4 address for the watch.";
    setStatus("Wi-Fi probe needs a watch IP address.");
    return;
  }
  let ports;
  try {
    ports = parseWifiPorts(wifiPortsInput?.value || "");
  } catch (error) {
    wifiProbeSummary.textContent = messageOf(error);
    setStatus("Wi-Fi probe ports are invalid.");
    return;
  }

  wifiProbeAbortController = new AbortController();
  isWifiProbing = true;
  updateButtons();
  wifiProbeSummary.textContent = `Probing ${ip}...`;
  setStatus(`Wi-Fi probe running against ${ip}.`);
  log(`Wi-Fi probe started for ${ip}; ports ${ports.join(", ")}.`);
  log("Browser limit: HTTPS pages and iOS may block local HTTP probes. A positive result is useful; failures are not definitive.");

  const results = [];
  try {
    for (const port of ports) {
      throwIfAborted(wifiProbeAbortController.signal);
      for (const scheme of wifiProbeSchemesForPort(port)) {
        throwIfAborted(wifiProbeAbortController.signal);
        const result = await probeWifiUrl(buildWifiProbeUrl(ip, port, scheme), wifiProbeAbortController.signal);
        results.push({ port, scheme, ...result });
        const marker = result.ok ? "reachable" : result.status;
        log(`Wi-Fi probe ${scheme} ${ip}:${port}: ${marker} in ${result.elapsedMs} ms${result.note ? ` (${result.note})` : ""}.`);
        wifiProbeSummary.textContent = wifiProbeSummaryText(ip, results);
      }
    }
  } catch (error) {
    if (isAbortError(error) || wifiProbeAbortController.signal.aborted) {
      log("Wi-Fi probe stopped.");
      setStatus("Wi-Fi probe stopped.");
    } else {
      showError("Wi-Fi probe failed", error);
    }
  } finally {
    isWifiProbing = false;
    wifiProbeAbortController = null;
    updateButtons();
    wifiProbeSummary.textContent = wifiProbeSummaryText(ip, results);
    const positives = results.filter((item) => item.ok);
    if (positives.length) {
      setStatus(`Wi-Fi probe found ${positives.length} browser-reachable endpoint(s).`);
    } else if (results.length) {
      setStatus("Wi-Fi probe found no browser-reachable local service.");
    }
  }
}

function stopWifiProbe() {
  wifiProbeAbortController?.abort?.();
  wifiProbeSummary.textContent = "Stopping Wi-Fi probe...";
  updateButtons();
}

async function probeWifiUrl(url, signal) {
  const startedAt = performance.now();
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), WIFI_PROBE_TIMEOUT_MS);
  const abortHandler = () => controller.abort();
  signal?.addEventListener?.("abort", abortHandler, { once: true });
  try {
    await fetch(url, {
      method: "GET",
      mode: "no-cors",
      cache: "no-store",
      signal: controller.signal
    });
    return {
      ok: true,
      status: "opaque-response",
      elapsedMs: Math.round(performance.now() - startedAt),
      note: "browser completed request"
    };
  } catch (error) {
    const elapsedMs = Math.round(performance.now() - startedAt);
    if (signal?.aborted) throw abortError();
    if (controller.signal.aborted) {
      return { ok: false, status: "timeout", elapsedMs, note: `${WIFI_PROBE_TIMEOUT_MS} ms` };
    }
    return {
      ok: false,
      status: "blocked-or-closed",
      elapsedMs,
      note: classifyWifiProbeError(error, url)
    };
  } finally {
    window.clearTimeout(timer);
    signal?.removeEventListener?.("abort", abortHandler);
  }
}

function buildWifiProbeUrl(ip, port, scheme) {
  const defaultPort = scheme === "https" ? 443 : 80;
  const portText = port === defaultPort ? "" : `:${port}`;
  return `${scheme}://${ip}${portText}/?garmin_prg_probe=${Date.now()}`;
}

function wifiProbeSchemesForPort(port) {
  if (port === 443 || port === 8443) return ["https"];
  if (location.protocol === "https:") return ["https", "http"];
  return ["http", "https"];
}

function normalizeWifiIp(value) {
  const text = value.trim();
  const match = text.match(/^([0-9]{1,3})(?:\.([0-9]{1,3})){3}$/);
  if (!match) return "";
  const parts = text.split(".").map((part) => Number(part));
  if (parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return "";
  if (parts[0] === 0 || parts[0] >= 224) return "";
  return parts.join(".");
}

function parseWifiPorts(value) {
  const ports = value
    .split(/[,\s]+/)
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => Number(part));
  if (!ports.length) throw new Error("Enter at least one TCP port.");
  if (ports.some((port) => !Number.isInteger(port) || port < 1 || port > 65535)) {
    throw new Error("Ports must be numbers from 1 to 65535.");
  }
  const unique = Array.from(new Set(ports));
  if (unique.length > WIFI_MAX_PORTS) {
    throw new Error(`Use ${WIFI_MAX_PORTS} ports or fewer for the browser probe.`);
  }
  return unique;
}

function wifiProbeSummaryText(ip, results) {
  if (!results.length) return `No Wi-Fi probe results yet for ${ip}.`;
  const positives = results.filter((item) => item.ok);
  if (positives.length) {
    return `Possible service on ${ip}: ${positives.map((item) => `${item.scheme}:${item.port}`).join(", ")}`;
  }
  const timeouts = results.filter((item) => item.status === "timeout").length;
  return `No browser-reachable service found on ${ip}. ${timeouts}/${results.length} probe(s) timed out.`;
}

function classifyWifiProbeError(error, url) {
  const message = messageOf(error);
  if (location.protocol === "https:" && url.startsWith("http://")) {
    return "possibly blocked as mixed content";
  }
  if (message.toLowerCase().includes("certificate")) return "certificate rejected";
  return message || "request failed";
}

async function connectWatch() {
  if (!selectedDevice) return;
  try {
    setBusy(true);
    setStatus("Connecting...");
    connection = await connectGarminTransport(selectedDevice, {
      writeFragmentSize: readNumber(fragmentSizeInput, 20),
      writeDelayMs: readNumber(writeDelayInput, 0),
      reliableMlr: Boolean(reliableMlrInput?.checked)
    });
    setTargetConfirmed(false);
    updateWatchIdentity(`Connected using Garmin ${connection.kind}`);
    updateTrustedWatchUi();
    if (hasTrustedMismatch()) {
      setStatus("Connected device does not match the trusted watch. Clear or replace the trusted watch to send.");
      log("Connected device does not match the trusted watch; upload is blocked.");
    } else if (!trustedDevice) {
      setStatus(`Connected using Garmin ${connection.kind}. Use Remember after confirming this is the right watch.`);
    } else {
      setStatus(`Connected using Garmin ${connection.kind} transport.`);
    }
    log(`Connected using Garmin ${connection.kind} transport. Confirm the target before sending.`);
  } catch (error) {
    connection = null;
    setTargetConfirmed(false);
    updateWatchIdentity("Connection failed");
    showError("Connection failed", error);
  } finally {
    setBusy(false);
  }
}

async function sendPrg({ benchmark = false, retry = false } = {}) {
  if (!selectedFile || !connection || !targetConfirmed || hasTrustedMismatch()) return;
  if (isUploading) return;
  const failedBenchmarkProfiles = retry && lastUploadRequest?.benchmark === benchmark
    ? new Set(lastUploadRequest.failedBenchmarkProfiles || [])
    : new Set();
  rememberUploadRequest(benchmark, failedBenchmarkProfiles);
  setRetryAvailable(false);
  uploadAbortController = new AbortController();
  const signal = uploadAbortController.signal;
  try {
    isUploading = true;
    setBusy(true);
    foregroundWarning.textContent = "Keep Bluefy open in the foreground until upload reaches 100%. Calls, lock screen, or app switching can break the transfer.";
    await requestWakeLock("upload start");
    const maxAttempts = benchmark ? MAX_BENCHMARK_RESTARTS + 1 : 1;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        await sendPrgAttempt({ benchmark, failedBenchmarkProfiles, attempt, signal });
        clearRetryState();
        return;
      } catch (error) {
        if (benchmark && error?.benchmarkProfile) {
          failedBenchmarkProfiles.add(benchmarkProfileKey(error.benchmarkProfile));
          rememberUploadRequest(benchmark, failedBenchmarkProfiles);
        }
        if (!benchmark || !error?.benchmarkProfile || attempt >= maxAttempts) throw error;
        const profile = error.benchmarkProfile;
        log(`Benchmark profile failed and will be skipped: ${profile.label}. ${messageOf(error.cause || error)}`);
        setStatus(`Benchmark profile failed: ${profile.label}. Reconnecting and trying the next setting...`);
        throwIfAborted(signal);
        await reconnectForBenchmarkRetry(currentUploadSettings());
      }
    }
  } catch (error) {
    setRetryAvailable(true);
    if (isAbortError(error) || signal.aborted) {
      setStatus("Upload stopped. Retry is available.");
      log("Upload stopped before completion. Retry will reconnect and restart from zero.");
    } else {
      showError("Upload failed", error);
    }
  } finally {
    isUploading = false;
    uploadAbortController = null;
    releaseWakeLock();
    foregroundWarning.textContent = "Keep Bluefy open in the foreground until upload reaches 100%.";
    setBusy(false);
  }
}

async function sendPrgAttempt({ benchmark, failedBenchmarkProfiles, attempt, signal }) {
  setProgress(0, 0, selectedFile.size);
  let uploadStats = null;
  const baseSettings = currentUploadSettings();
  let settings = baseSettings;
  if (benchmark) {
    const candidates = buildBenchmarkProfiles(baseSettings, selectedFile.size, failedBenchmarkProfiles);
    if (!candidates.length) throw new Error("No benchmark profiles remain to try.");
    settings = candidates[0];
    applyTuningSettings(settings);
    log(`Benchmark Send attempt ${attempt}: trying ${settings.label}; ${candidates.length - 1} fallback profile(s) remain.`);
  }
  applyTransportSettings(connection, settings);
  log(`Upload attempt ${attempt}. Settings: GFDI packet ${settings.maxPacketSize}, BLE fragment ${settings.fragmentSize}, pipeline ${settings.pipelineWindow}, write delay ${settings.writeDelayMs} ms.`);
  if (benchmark) {
    log("Benchmark Send now tests one profile for the whole upload. Failed profiles reconnect and restart from zero with the next profile.");
    if (riskyPipelineInput?.checked) log("Risky pipeline profiles are enabled; failed profiles will trigger reconnect/retry.");
  }
  if (settings.maxPacketSize > SAFE_GFDI_PACKET_SIZE) {
    log(`Experimental GFDI packet size ${settings.maxPacketSize}. If this stalls or fails, retry with ${SAFE_GFDI_PACKET_SIZE}.`);
  }
  if (settings.maxPacketSize > LARGE_GFDI_PACKET_SIZE) {
    log("Large GFDI packets are probing the watch/MLR breaking point. Stop + Retry is expected if the watch stops ACKing.");
  }
  if (settings.fragmentSize > SAFE_BLE_FRAGMENT_SIZE) {
    log(`Experimental BLE fragment ${settings.fragmentSize}. Your iPhone/WebBLE path previously stalled above ${SAFE_BLE_FRAGMENT_SIZE}; use Stop + Retry if writes hang.`);
  }
  if (settings.pipelineWindow > 1) {
    log(`Experimental pipeline window ${settings.pipelineWindow}. If upload fails, retry with Pipeline chunks 1.`);
  }
  try {
    await uploadPrg(selectedFile.data, connection, {
      ...settings,
      benchmarkProfiles: null,
      timeoutMs: 30000,
      maxRetries: 5,
      signal,
      onProgress: ({ offset, total }) => {
        if (!uploadStats) uploadStats = createTransferStats(total);
        setProgress(Math.floor((100 * offset) / total), offset, total, uploadStats);
      }
    });
  } catch (error) {
    if (isAbortError(error) || signal?.aborted) throw error;
    if (benchmark) throw benchmarkProfileFailure(settings, error);
    throw error;
  }
  setProgress(100, selectedFile.size, selectedFile.size, uploadStats);
  const transferMetrics = uploadStats ? completedTransferMetrics(uploadStats, selectedFile.size) : null;
  const transferSummary = transferMetrics ? transferSummaryText(transferMetrics) : "";
  setStatus(transferSummary ? `Upload complete. ${transferSummary} Let Garmin Connect reconnect to register the app.` : "Upload complete. Let Garmin Connect reconnect to register the app.");
  if (transferSummary) log(transferSummary);
  if (transferMetrics) recordTuningResult({
    ...currentUploadSettings(),
    avgBps: transferMetrics.avgBps,
    elapsedSec: transferMetrics.elapsedSec,
    fileSize: selectedFile.size,
    transportKind: connection.kind
  });
  log("Upload complete. Garmin Connect must perform the registration pass.");
}

async function reconnectForBenchmarkRetry(settings) {
  return reconnectForRetry(settings, "benchmark retry");
}

async function retryLastUpload() {
  if (!lastUploadRequest || !selectedFile || !selectedDevice || hasTrustedMismatch()) return;
  if (isUploading) {
    await stopActiveUpload("Stop + Retry requested. Restarting from zero.");
    await waitForUploadIdle(3000);
    if (isUploading) {
      setStatus("Stop sent. Waiting for Bluefy to release Bluetooth; tap Retry again in a moment.");
      return;
    }
  }
  const benchmark = Boolean(lastUploadRequest.benchmark);
  const settings = currentUploadSettings();
  try {
    setBusy(true);
    setStatus("Retrying: reconnecting to watch...");
    log(`Retry requested for ${benchmark ? "Benchmark Send" : "Send PRG"}.`);
    await reconnectForRetry(settings, "manual retry");
  } catch (error) {
    setRetryAvailable(true);
    showError("Retry reconnect failed", error);
    return;
  } finally {
    setBusy(false);
  }
  await sendPrg({ benchmark, retry: true });
}

async function stopActiveUpload(message) {
  if (!isUploading) return;
  setRetryAvailable(true);
  setStatus(message || "Stopping upload...");
  log(`${message || "Stopping upload."} Disconnecting watch to break the active transfer.`);
  uploadAbortController?.abort?.();
  try {
    connection?.close?.();
    selectedDevice?.gatt?.disconnect?.();
  } catch (error) {
    log(`Disconnect during stop failed: ${messageOf(error)}`);
  }
  connection = null;
  setTargetConfirmed(false);
  releaseWakeLock();
  updateButtons();
}

async function waitForUploadIdle(timeoutMs) {
  const startedAt = performance.now();
  while (isUploading && performance.now() - startedAt < timeoutMs) {
    await sleep(100);
  }
}

async function reconnectForRetry(settings, reason) {
  try {
    connection?.close?.();
    selectedDevice?.gatt?.disconnect?.();
  } catch (error) {
    log(`Disconnect before ${reason} failed: ${messageOf(error)}`);
  }
  connection = null;
  setTargetConfirmed(false);
  updateButtons();
  await sleep(1500);
  connection = await connectGarminTransport(selectedDevice, {
    writeFragmentSize: settings.fragmentSize,
    writeDelayMs: settings.writeDelayMs,
    reliableMlr: Boolean(reliableMlrInput?.checked)
  });
  updateWatchIdentity(`Connected using Garmin ${connection.kind}`);
  updateTrustedWatchUi();
  if (hasTrustedMismatch()) throw new Error("Reconnected device does not match the trusted watch.");
  setTargetConfirmed(true);
  log(`Reconnected using Garmin ${connection.kind} transport for ${reason}.`);
}

async function requestWakeLock(reason) {
  if (!keepAwakeInput?.checked) return;
  if (document.hidden) return;
  if (!("wakeLock" in navigator) || typeof navigator.wakeLock.request !== "function") {
    foregroundWarning.textContent = "Screen wake lock is not supported here. Keep Bluefy open and stop the phone from locking.";
    return;
  }
  if (wakeLock) return;
  wakeLock = await navigator.wakeLock.request("screen");
  wakeLock.addEventListener?.("release", () => {
    wakeLock = null;
    log("Screen wake lock released.");
  });
  log(`Screen wake lock active (${reason}).`);
}

function releaseWakeLock() {
  const lock = wakeLock;
  wakeLock = null;
  if (lock && typeof lock.release === "function") {
    lock.release().catch((error) => log(`Screen wake lock release failed: ${messageOf(error)}`));
  }
}

async function connectGarminTransport(device, options) {
  const server = await device.gatt.connect();
  try {
    const v2 = await tryV2Transport(server, options);
    if (v2) return v2;
  } catch (error) {
    log(`v2 transport failed: ${messageOf(error)}`);
  }
  try {
    const v1 = await tryKnownPair(server, UUIDS.v1Service, UUIDS.v1Receive, UUIDS.v1Send, "v1", options);
    if (v1) return v1;
  } catch (error) {
    log(`v1 transport failed: ${messageOf(error)}`);
  }
  const v0 = await tryKnownPair(server, UUIDS.v0Service, UUIDS.v0Receive, UUIDS.v0Send, "v0", options);
  if (v0) return v0;
  throw new Error("No supported Garmin GFDI transport found.");
}

async function tryV2Transport(server, options) {
  const service = await server.getPrimaryService(UUIDS.v2Service);
  for (let value = 0x2810; value < 0x2815; value += 1) {
    const receiveUuid = gfdiUuid(value);
    const sendUuid = gfdiUuid(value + 0x10);
    try {
      const receive = await service.getCharacteristic(receiveUuid);
      const send = await service.getCharacteristic(sendUuid);
      const transport = new V2Transport(receive, send, options);
      await transport.initialize();
      return transport;
    } catch (error) {
      log(`v2 pair ${receiveUuid}/${sendUuid} unavailable: ${messageOf(error)}`);
    }
  }
  return null;
}

async function tryKnownPair(server, serviceUuid, receiveUuid, sendUuid, kind, options) {
  const service = await server.getPrimaryService(serviceUuid);
  const receive = await service.getCharacteristic(receiveUuid);
  const send = await service.getCharacteristic(sendUuid);
  const transport = new V1Transport(receive, send, kind, options);
  await transport.initialize();
  return transport;
}

class BaseTransport {
  constructor(receive, send, kind, options) {
    this.receive = receive;
    this.send = send;
    this.kind = kind;
    this.writeFragmentSize = clampNumber(options.writeFragmentSize, SAFE_BLE_FRAGMENT_SIZE, MAX_BLE_FRAGMENT_SIZE, SAFE_BLE_FRAGMENT_SIZE);
    this.writeDelayMs = clampNumber(options.writeDelayMs, 0, 25, 0);
    this.decoder = new CobsDecoder();
    this.messages = [];
    this.waiters = [];
  }

  async initialize() {
    await this.receive.startNotifications();
    this.receive.addEventListener("characteristicvaluechanged", (event) => {
      this.onNotify(dataViewToBytes(event.target.value));
    });
  }

  receiveGfdi(timeoutMs, signal) {
    throwIfAborted(signal);
    const ready = this.messages.shift();
    if (ready) return Promise.resolve(ready);
    return new Promise((resolve, reject) => {
      let timeout = null;
      let abortHandler = null;
      const cleanup = () => {
        if (timeout !== null) clearTimeout(timeout);
        if (abortHandler) signal?.removeEventListener?.("abort", abortHandler);
        const index = this.waiters.indexOf(waiter);
        if (index >= 0) this.waiters.splice(index, 1);
      };
      const waiter = (message) => {
        cleanup();
        resolve(message);
      };
      timeout = setTimeout(() => {
        cleanup();
        reject(new Error(`Timed out waiting for GFDI response after ${timeoutMs}ms`));
      }, timeoutMs);
      this.waiters.push(waiter);
      if (signal) {
        abortHandler = () => {
          cleanup();
          reject(abortError());
        };
        signal.addEventListener("abort", abortHandler, { once: true });
        if (signal.aborted) abortHandler();
      }
    });
  }

  enqueueDecoded(data) {
    for (const message of this.decoder.feed(data)) {
      const waiter = this.waiters.shift();
      if (waiter) waiter(message);
      else this.messages.push(message);
    }
  }

  async writeRaw(bytes) {
    if (typeof this.send.writeValueWithoutResponse === "function") {
      await this.send.writeValueWithoutResponse(bytes);
    } else if (typeof this.send.writeValueWithResponse === "function") {
      await this.send.writeValueWithResponse(bytes);
    } else {
      await this.send.writeValue(bytes);
    }
    if (this.writeDelayMs > 0) await sleep(this.writeDelayMs);
  }
}

class V1Transport extends BaseTransport {
  onNotify(data) {
    this.enqueueDecoded(data);
  }

  async sendGfdi(packet, signal = null) {
    const encoded = cobsEncode(packet);
    for (let offset = 0; offset < encoded.length; offset += this.writeFragmentSize) {
      throwIfAborted(signal);
      await this.writeRaw(encoded.slice(offset, offset + this.writeFragmentSize));
    }
  }
}

class V2Transport extends BaseTransport {
  constructor(receive, send, options) {
    super(receive, send, "v2", options);
    this.gfdiHandle = null;
    this.reliableMlrRequested = Boolean(options.reliableMlr);
    this.mlr = null;
  }

  async initialize() {
    await super.initialize();
    if (this.reliableMlrRequested) log("Requesting reliable MLR mode for Garmin GFDI.");
    await this.writeRaw(closeAllServices());
    await this.waitForGfdiHandle(15000);
  }

  onNotify(value) {
    if (!value.length) return;
    if ((value[0] & MLR_FLAG_MASK) !== 0 && this.mlr) {
      this.mlr.onPacketReceived(value);
      return;
    }
    const handle = value[0];
    const body = value.slice(1);
    if (handle === 0) {
      this.handleManagement(body);
      return;
    }
    if (this.gfdiHandle !== null && handle === this.gfdiHandle) {
      this.enqueueDecoded(body);
    }
  }

  async sendGfdi(packet, signal = null) {
    if (this.gfdiHandle === null) throw new Error("v2 GFDI handle is not registered.");
    const encoded = cobsEncode(packet);
    if (this.mlr) {
      await this.mlr.sendMessage(encoded, signal);
      return;
    }
    const fragmentSize = Math.max(1, this.writeFragmentSize - 1);
    for (let offset = 0; offset < encoded.length; offset += fragmentSize) {
      throwIfAborted(signal);
      const fragment = encoded.slice(offset, offset + fragmentSize);
      await this.writeRaw(concatBytes(Uint8Array.of(this.gfdiHandle), fragment));
    }
  }

  close() {
    this.mlr?.close?.();
  }

  handleManagement(data) {
    if (data.length < 9) return;
    const requestType = data[0];
    const clientId = readU64Low(data, 1);
    if (clientId !== GADGETBRIDGE_CLIENT_ID) return;
    if (requestType === REQUEST_CLOSE_ALL_RESP) {
      this.writeRaw(registerService(SERVICE_GFDI, this.reliableMlrRequested)).catch((error) => {
        this.handleReject?.(error);
      });
      return;
    }
    if (requestType === REQUEST_REGISTER_ML_RESP) {
      if (data.length < 14) return;
      const serviceCode = readU16(data, 9);
      const status = data[11];
      const handle = data[12];
      const reliable = data[13];
      if (serviceCode !== SERVICE_GFDI) return;
      if (status !== 0) {
        this.handleReject?.(new Error(`Watch rejected v2 GFDI registration with status ${status}`));
        return;
      }
      this.gfdiHandle = handle;
      if (reliable) {
        this.mlr = new MlrSession(this, handle);
        this.kind = "v2 reliable MLR";
        log(`Garmin GFDI registered in reliable MLR mode; handle=${handle}.`);
      } else if (this.reliableMlrRequested) {
        log("Watch accepted GFDI but did not enable reliable MLR; using regular v2 ML.");
      }
      this.handleResolve?.();
    }
  }

  waitForGfdiHandle(timeoutMs) {
    if (this.gfdiHandle !== null) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Timed out registering v2 GFDI service.")), timeoutMs);
      this.handleResolve = () => {
        clearTimeout(timeout);
        resolve();
      };
      this.handleReject = (error) => {
        clearTimeout(timeout);
        reject(error);
      };
    });
  }
}

class MlrSession {
  constructor(transport, handle) {
    this.transport = transport;
    this.handle = handle;
    this.lastSendAck = 0;
    this.nextSendSeq = 0;
    this.nextRcvSeq = 0;
    this.lastRcvAck = 0;
    this.maxNumUnackedSend = MLR_INITIAL_MAX_UNACKED_SEND;
    this.retransmissionTimeoutMs = MLR_INITIAL_RETRANSMISSION_TIMEOUT_MS;
    this.sentFragments = new Array(MLR_MAX_SEQ_NUM + 1).fill(null);
    this.windowWaiters = [];
    this.ackTimer = null;
    this.retransmissionTimer = null;
    this.closed = false;
  }

  async sendMessage(message, signal = null) {
    if (!message?.length) return;
    const fragmentSize = Math.max(1, this.maxPacketSize() - 2);
    for (let offset = 0; offset < message.length; offset += fragmentSize) {
      throwIfAborted(signal);
      await this.waitForSendWindow(signal);
      const data = message.slice(offset, Math.min(message.length, offset + fragmentSize));
      const reqNum = this.nextRcvSeq;
      const seqNum = this.nextSendSeq;
      const packet = this.createPacket(reqNum, seqNum, data);
      this.sentFragments[seqNum] = { packet, reqNum, seqNum };
      this.nextSendSeq = this.nextSeq(this.nextSendSeq);
      await this.transport.writeRaw(packet);
      if (this.numSentUnacked() === 1) this.startRetransmissionTimer();
    }
  }

  onPacketReceived(packet) {
    if (packet.length < 2 || this.closed) return;
    const byte0 = packet[0] & 0xff;
    const byte1 = packet[1] & 0xff;
    const packetHandle = (byte0 & MLR_HANDLE_MASK) >> 4;
    if (packetHandle !== (this.handle & 0x07)) {
      log(`Ignoring MLR packet for handle ${packetHandle}; expected ${this.handle & 0x07}.`);
      return;
    }
    const reqNum = ((byte0 & MLR_REQ_NUM_MASK) << 2) | ((byte1 >> 6) & 0x03);
    const seqNum = byte1 & MLR_SEQ_NUM_MASK;
    if (reqNum !== this.lastRcvAck) this.processAck(reqNum);
    if (packet.length <= 2) return;

    if (seqNum === this.nextRcvSeq) {
      this.transport.enqueueDecoded(packet.slice(2));
      this.nextRcvSeq = this.nextSeq(this.nextRcvSeq);
      this.scheduleAckIfNeeded();
    } else {
      log(`MLR out-of-sequence packet; expected ${this.nextRcvSeq}, got ${seqNum}.`);
      this.sendAckPacket();
    }
  }

  processAck(reqNum) {
    const numAcked = this.sequenceDistance(this.lastRcvAck, reqNum);
    const numUnacked = this.numSentUnacked();
    if (numAcked === 0) return;
    if (numAcked > numUnacked) {
      log(`Ignoring MLR ACK ${reqNum}; only ${numUnacked} packet(s) unacked.`);
      return;
    }
    for (let seq = this.lastRcvAck; seq !== reqNum; seq = this.nextSeq(seq)) {
      this.sentFragments[seq] = null;
    }
    this.lastRcvAck = reqNum;
    this.stopRetransmissionTimer();
    if (this.lastRcvAck !== this.nextSendSeq) this.startRetransmissionTimer();
    this.notifyWindowWaiters();
  }

  async waitForSendWindow(signal) {
    while (!this.closed && this.numSentUnacked() >= this.maxNumUnackedSend) {
      await withTimeout(
        new Promise((resolve) => this.windowWaiters.push(resolve)),
        MLR_SEND_WINDOW_TIMEOUT_MS,
        "Timed out waiting for MLR send window",
        signal
      );
    }
    if (this.closed) throw new Error("MLR transport is closed.");
  }

  scheduleAckIfNeeded() {
    if (this.ackTimer) window.clearTimeout(this.ackTimer);
    const numRcvdUnacked = this.sequenceDistance(this.lastSendAck, this.nextRcvSeq);
    if (numRcvdUnacked >= MLR_ACK_TRIGGER_THRESHOLD) {
      this.sendAckPacket();
    } else {
      this.ackTimer = window.setTimeout(() => this.sendAckPacket(), MLR_ACK_TIMEOUT_MS);
    }
  }

  sendAckPacket() {
    if (this.closed) return;
    if (this.ackTimer) {
      window.clearTimeout(this.ackTimer);
      this.ackTimer = null;
    }
    const packet = this.createPacket(this.nextRcvSeq, 0, new Uint8Array(0));
    this.transport.writeRaw(packet).catch((error) => log(`MLR ACK write failed: ${messageOf(error)}`));
    this.lastSendAck = this.nextRcvSeq;
  }

  startRetransmissionTimer() {
    this.stopRetransmissionTimer();
    this.retransmissionTimer = window.setTimeout(() => this.onRetransmissionTimeout(), this.retransmissionTimeoutMs);
  }

  stopRetransmissionTimer() {
    if (this.retransmissionTimer) {
      window.clearTimeout(this.retransmissionTimer);
      this.retransmissionTimer = null;
    }
  }

  onRetransmissionTimeout() {
    if (this.closed) return;
    this.retransmissionTimeoutMs = Math.min(this.retransmissionTimeoutMs * 2, MLR_MAX_RETRANSMISSION_TIMEOUT_MS);
    this.maxNumUnackedSend = Math.max(1, Math.floor(this.maxNumUnackedSend / 2));
    log(`MLR retransmission timeout; window now ${this.maxNumUnackedSend}.`);
    for (let seq = this.lastRcvAck; seq !== this.nextSendSeq; seq = this.nextSeq(seq)) {
      const fragment = this.sentFragments[seq];
      if (fragment?.packet) {
        this.transport.writeRaw(fragment.packet).catch((error) => log(`MLR retransmission failed: ${messageOf(error)}`));
      }
    }
    this.startRetransmissionTimer();
    this.notifyWindowWaiters();
  }

  createPacket(reqNum, seqNum, data) {
    const packet = new Uint8Array(2 + data.length);
    packet[0] = MLR_FLAG_MASK | ((this.handle & 0x07) << 4) | ((reqNum >> 2) & MLR_REQ_NUM_MASK);
    packet[1] = ((reqNum & 0x03) << 6) | (seqNum & MLR_SEQ_NUM_MASK);
    packet.set(data, 2);
    return packet;
  }

  maxPacketSize() {
    return Math.max(3, this.transport.writeFragmentSize || 20);
  }

  numSentUnacked() {
    return this.sequenceDistance(this.lastRcvAck, this.nextSendSeq);
  }

  sequenceDistance(from, to) {
    return (to - from + MLR_MAX_SEQ_NUM + 1) % (MLR_MAX_SEQ_NUM + 1);
  }

  nextSeq(value) {
    return (value + 1) & MLR_MAX_SEQ_NUM;
  }

  notifyWindowWaiters() {
    const waiters = this.windowWaiters.splice(0);
    for (const resolve of waiters) resolve();
  }

  close() {
    this.closed = true;
    if (this.ackTimer) window.clearTimeout(this.ackTimer);
    this.stopRetransmissionTimer();
    this.notifyWindowWaiters();
    this.sentFragments.fill(null);
  }
}

async function uploadPrg(data, transport, options) {
  validatePrg(data);
  const timeoutMs = options.timeoutMs ?? 30000;
  const maxRetries = options.maxRetries ?? 5;
  const maxPacketSize = clampNumber(options.maxPacketSize, 64, MAX_EXPERIMENTAL_GFDI_PACKET_SIZE, SAFE_GFDI_PACKET_SIZE);
  const pipelineWindow = clampNumber(options.pipelineWindow, 1, MAX_PIPELINE_WINDOW, 1);
  const benchmarkProfiles = Array.isArray(options.benchmarkProfiles) ? options.benchmarkProfiles : [];
  const signal = options.signal;

  log("Sending SYNC_READY.");
  throwIfAborted(signal);
  await sendSystemEvent(transport, buildSyncReady(), timeoutMs, signal);

  log(`Creating PRG file slot (${data.length} bytes).`);
  throwIfAborted(signal);
  await sendGfdiChecked(transport, buildCreateFile(data.length), "CREATE_FILE", signal);
  const createStatus = await receiveKind(transport, "createFile", timeoutMs, signal);
  if (createStatus.status !== Status.ACK || createStatus.createStatus !== CreateStatus.OK) {
    throw new Error(describeCreateFileFailure(createStatus, data.length));
  }
  if (createStatus.dataType !== PRG_TYPE || createStatus.subtype !== PRG_SUBTYPE) {
    throw new Error(`Watch created unexpected file type ${createStatus.dataType}/${createStatus.subtype}`);
  }
  options.onProgress?.({ offset: 0, total: data.length });

  log(`Starting upload to file index ${createStatus.fileIndex}.`);
  throwIfAborted(signal);
  await sendGfdiChecked(transport, buildUploadRequest(createStatus.fileIndex, data.length), "UPLOAD_REQUEST", signal);
  const uploadStatus = await receiveKind(transport, "uploadRequest", timeoutMs, signal);
  if (uploadStatus.status !== Status.ACK || uploadStatus.uploadStatus !== UploadStatus.OK) {
    throw new Error(`Upload request failed: ${JSON.stringify(uploadStatus)}`);
  }
  if (uploadStatus.maxFileSize && data.length > uploadStatus.maxFileSize) {
    throw new Error(`Watch max file size is ${uploadStatus.maxFileSize}; PRG is ${data.length}.`);
  }
  if (uploadStatus.dataOffset > data.length) {
    throw new Error(`Watch requested offset beyond PRG size: ${uploadStatus.dataOffset}.`);
  }

  const initialCrc = uploadStatus.dataOffset > 0 && uploadStatus.crcSeed === 0 ? undefined : uploadStatus.crcSeed;
  const chunker = new UploadChunker(data, maxPacketSize, uploadStatus.dataOffset, initialCrc);
  options.onProgress?.({ offset: uploadStatus.dataOffset, total: data.length });

  const benchmarkBest = benchmarkProfiles.length
    ? await uploadBenchmarkProfiles(data, transport, chunker, timeoutMs, maxRetries, benchmarkProfiles, options)
    : null;
  const finalSettings = benchmarkBest || { maxPacketSize, pipelineWindow, fragmentSize: options.fragmentSize, writeDelayMs: options.writeDelayMs };
  applyTransportSettings(transport, finalSettings);
  chunker.setMaxPacketSize(finalSettings.maxPacketSize);

  if (finalSettings.pipelineWindow <= 1) {
    await uploadSequentialChunks(data, transport, chunker, timeoutMs, maxRetries, options);
  } else {
    await uploadPipelinedChunks(data, transport, chunker, timeoutMs, finalSettings.pipelineWindow, options);
  }

  log("Sending SYNC_COMPLETE.");
  throwIfAborted(signal);
  await sendSystemEvent(transport, buildSyncComplete(), timeoutMs, signal);
  await sleep(2000);
}

async function uploadBenchmarkProfiles(data, transport, chunker, timeoutMs, maxRetries, profiles, options) {
  const results = [];
  for (const profile of profiles) {
    if (chunker.offset >= data.length) break;
    const bytesToTest = benchmarkBytesForProfile(profile, data.length - chunker.offset);
    if (bytesToTest <= 0) break;
    applyTransportSettings(transport, profile);
    chunker.setMaxPacketSize(profile.maxPacketSize);
    const startOffset = chunker.offset;
    const stopOffset = Math.min(data.length, startOffset + bytesToTest);
    const startedAt = performance.now();
    log(`Benchmarking ${profile.label}: ${formatBytes(stopOffset - startOffset)}.`);
    try {
      await withTimeout(
        profile.pipelineWindow <= 1
          ? uploadSequentialChunks(data, transport, chunker, timeoutMs, maxRetries, options, stopOffset)
          : uploadPipelinedChunks(data, transport, chunker, timeoutMs, profile.pipelineWindow, options, stopOffset),
        BENCHMARK_PROFILE_TIMEOUT_MS,
        `Benchmark profile timed out after ${Math.round(BENCHMARK_PROFILE_TIMEOUT_MS / 1000)}s`,
        options.signal
      );
    } catch (error) {
      throw benchmarkProfileFailure(profile, error);
    }
    const elapsedSec = Math.max((performance.now() - startedAt) / 1000, 0);
    const bytes = Math.max(0, chunker.offset - startOffset);
    const avgBps = elapsedSec > 0 ? bytes / elapsedSec : 0;
    const result = { ...profile, bytes, elapsedSec, avgBps };
    results.push(result);
    options.onBenchmarkProfile?.(result);
    recordTuningResult({
      ...result,
      fileSize: data.length,
      transportKind: transport.kind
    });
  }
  if (!results.length) return null;
  const best = results
    .filter((result) => Number.isFinite(result.avgBps) && result.avgBps > 0)
    .sort((left, right) => right.avgBps - left.avgBps)[0] || null;
  if (best) options.onBenchmarkSelected?.(best);
  return best;
}

function benchmarkProfileFailure(profile, error) {
  const wrapped = new Error(`Benchmark profile failed: ${profile.label}. ${messageOf(error)}`);
  wrapped.benchmarkProfile = profile;
  wrapped.cause = error;
  return wrapped;
}

function benchmarkBytesForProfile(profile, remainingBytes) {
  const packetPayload = Math.max(1, profile.maxPacketSize - 13);
  const target = Math.max(BENCHMARK_MIN_BYTES, packetPayload * Math.max(12, profile.pipelineWindow * 6));
  return Math.min(remainingBytes, Math.min(BENCHMARK_MAX_BYTES, target));
}

async function uploadSequentialChunks(data, transport, chunker, timeoutMs, maxRetries, options, stopOffset = data.length) {
  let retries = 0;
  while (true) {
    throwIfAborted(options.signal);
    const chunk = chunker.nextChunk(stopOffset);
    if (!chunk) break;

    await sendGfdiChecked(transport, buildFileTransferData(chunk.data, chunk.offset, chunk.runningCrc), "FILE_TRANSFER_DATA", options.signal);
    const transferStatus = await receiveKind(transport, "fileTransferData", timeoutMs, options.signal);
    if (transferStatus.status !== Status.ACK || transferStatus.transferStatus !== TransferStatus.OK) {
      if (canRetryTransfer(transferStatus, data.length, retries, maxRetries)) {
        retries += 1;
        chunker.seek(transferStatus.dataOffset);
        options.onProgress?.({ offset: transferStatus.dataOffset, total: data.length });
        continue;
      }
      throw new Error(`File chunk failed: ${JSON.stringify(transferStatus)}`);
    }

    const expectedOffset = chunk.offset + chunk.data.length;
    if (transferStatus.dataOffset !== expectedOffset) {
      if (transferStatus.dataOffset < expectedOffset && canRetryOffset(transferStatus.dataOffset, data.length, retries, maxRetries)) {
        retries += 1;
        chunker.seek(transferStatus.dataOffset);
        options.onProgress?.({ offset: transferStatus.dataOffset, total: data.length });
        continue;
      }
      throw new Error(`Watch acknowledged offset ${transferStatus.dataOffset}, expected ${expectedOffset}.`);
    }

    retries = 0;
    options.onProgress?.({ offset: transferStatus.dataOffset, total: data.length });
  }
}

async function uploadPipelinedChunks(data, transport, chunker, timeoutMs, pipelineWindow, options, stopOffset = data.length) {
  while (true) {
    throwIfAborted(options.signal);
    const batch = [];
    for (let index = 0; index < pipelineWindow; index += 1) {
      throwIfAborted(options.signal);
      const chunk = chunker.nextChunk(stopOffset);
      if (!chunk) break;
      await sendGfdiChecked(transport, buildFileTransferData(chunk.data, chunk.offset, chunk.runningCrc), "FILE_TRANSFER_DATA", options.signal);
      batch.push(chunk);
    }
    if (!batch.length) break;

    for (const chunk of batch) {
      throwIfAborted(options.signal);
      const transferStatus = await receiveKind(transport, "fileTransferData", timeoutMs, options.signal);
      const expectedOffset = chunk.offset + chunk.data.length;
      if (transferStatus.status !== Status.ACK || transferStatus.transferStatus !== TransferStatus.OK) {
        throw new Error(`Pipelined file chunk failed at offset ${chunk.offset}; retry with Pipeline chunks 1. Status: ${JSON.stringify(transferStatus)}`);
      }
      if (transferStatus.dataOffset !== expectedOffset) {
        throw new Error(`Pipelined upload lost alignment at offset ${chunk.offset}; watch acknowledged ${transferStatus.dataOffset}, expected ${expectedOffset}. Retry with Pipeline chunks 1.`);
      }
      options.onProgress?.({ offset: transferStatus.dataOffset, total: data.length });
    }
  }
}

async function sendSystemEvent(transport, packet, timeoutMs, signal) {
  await sendGfdiChecked(transport, packet, "SYSTEM_EVENT", signal);
  const status = await receiveGenericStatus(transport, GarminMessage.SYSTEM_EVENT, timeoutMs, signal);
  if (status.status !== Status.ACK) {
    throw new Error(`System event failed: ${JSON.stringify(status)}`);
  }
}

async function sendGfdiChecked(transport, packet, label, signal) {
  throwIfAborted(signal);
  await withTimeout(
    transport.sendGfdi(packet, signal),
    GFDI_WRITE_TIMEOUT_MS,
    `${label} write timed out after ${Math.round(GFDI_WRITE_TIMEOUT_MS / 1000)}s`,
    signal
  );
}

async function receiveGenericStatus(transport, originalMessageType, timeoutMs, signal) {
  while (true) {
    throwIfAborted(signal);
    const message = parseGfdi(await transport.receiveGfdi(timeoutMs, signal));
    if (message.kind === "generic" && message.originalMessageType === originalMessageType) return message;
  }
}

async function receiveKind(transport, kind, timeoutMs, signal) {
  while (true) {
    throwIfAborted(signal);
    const message = parseGfdi(await transport.receiveGfdi(timeoutMs, signal));
    if (message.kind === kind) return message;
  }
}

function canRetryTransfer(status, total, retries, maxRetries) {
  return [TransferStatus.RESEND, TransferStatus.CRC_MISMATCH, TransferStatus.OFFSET_MISMATCH, TransferStatus.SYNC_PAUSED].includes(status.transferStatus)
    && retries < maxRetries
    && status.dataOffset >= 0
    && status.dataOffset <= total;
}

function canRetryOffset(offset, total, retries, maxRetries) {
  return retries < maxRetries && offset >= 0 && offset <= total;
}

class UploadChunker {
  constructor(data, maxPacketSize, initialOffset = 0, initialCrc = undefined) {
    if (maxPacketSize <= 13) throw new Error("GFDI packet size must be greater than 13.");
    this.data = data;
    this.setMaxPacketSize(maxPacketSize);
    this.offset = initialOffset;
    this.runningCrc = initialCrc === undefined ? garminCrc(data.slice(0, initialOffset)) : initialCrc & 0xffff;
  }

  setMaxPacketSize(maxPacketSize) {
    if (maxPacketSize <= 13) throw new Error("GFDI packet size must be greater than 13.");
    this.maxPayloadSize = maxPacketSize - 13;
  }

  seek(offset, runningCrc = undefined) {
    if (offset < 0 || offset > this.data.length) throw new Error("Offset is outside the upload data.");
    this.offset = offset;
    this.runningCrc = runningCrc === undefined ? garminCrc(this.data.slice(0, offset)) : runningCrc & 0xffff;
  }

  nextChunk(stopOffset = this.data.length) {
    const limit = Math.min(this.data.length, Math.max(0, stopOffset));
    if (this.offset >= limit) return null;
    const data = this.data.slice(this.offset, Math.min(limit, this.offset + this.maxPayloadSize));
    const offset = this.offset;
    this.runningCrc = garminCrc(data, this.runningCrc);
    this.offset += data.length;
    return { offset, data, runningCrc: this.runningCrc };
  }
}

function validatePrg(data) {
  if (data.length > MAX_EXPECTED_PRG_SIZE) throw new Error(`PRG is larger than ${MAX_EXPECTED_PRG_SIZE} bytes.`);
  for (let index = 0; index < PRG_MAGIC.length; index += 1) {
    if (data[index] !== PRG_MAGIC[index]) {
      const got = Array.from(data.slice(0, 3)).map((value) => value.toString(16).padStart(2, "0").toUpperCase()).join(" ");
      throw new Error(`Not a Garmin PRG; expected D0 00 D0, got ${got}.`);
    }
  }
}

function buildCreateFile(fileSize) {
  const nonceLow = Math.floor(Math.random() * 0xffffffff) >>> 0;
  const nonceHigh = Math.floor(Math.random() * 0xffffffff) >>> 0;
  const payload = new ByteWriter()
    .u32(fileSize)
    .u8(PRG_TYPE)
    .u8(PRG_SUBTYPE)
    .u16(0)
    .u8(0)
    .u8(0)
    .u16(0xffff)
    .u16(0)
    .u32(nonceLow)
    .u32(nonceHigh)
    .toBytes();
  return frameGfdi(GarminMessage.CREATE_FILE, payload);
}

function buildUploadRequest(fileIndex, fileSize, dataOffset = 0, crcSeed = 0) {
  return frameGfdi(GarminMessage.UPLOAD_REQUEST, new ByteWriter().u16(fileIndex).u32(fileSize).u32(dataOffset).u16(crcSeed).toBytes());
}

function buildFileTransferData(chunk, dataOffset, runningCrc) {
  const header = new ByteWriter().u8(0).u16(runningCrc).u32(dataOffset).toBytes();
  return frameGfdi(GarminMessage.FILE_TRANSFER_DATA, concatBytes(header, chunk));
}

function buildSyncReady() {
  return buildSystemEvent(SystemEvent.SYNC_READY);
}

function buildSyncComplete() {
  return buildSystemEvent(SystemEvent.SYNC_COMPLETE);
}

function buildSystemEvent(event, value = 0) {
  return frameGfdi(GarminMessage.SYSTEM_EVENT, new ByteWriter().u8(event).u8(value).toBytes());
}

function frameGfdi(messageType, payload = new Uint8Array()) {
  const withoutCrc = new ByteWriter().u16(2 + 2 + payload.length + 2).u16(messageType).bytes(payload).toBytes();
  return concatBytes(withoutCrc, new ByteWriter().u16(garminCrc(withoutCrc)).toBytes());
}

function parseGfdi(packet) {
  if (packet.length < 6) throw new Error(`GFDI packet too short: ${packet.length} bytes.`);
  const length = readU16(packet, 0);
  if (length !== packet.length) throw new Error(`GFDI length mismatch: header=${length}, actual=${packet.length}.`);
  const expectedCrc = readU16(packet, length - 2);
  const actualCrc = garminCrc(packet.slice(0, length - 2));
  if (expectedCrc !== actualCrc) throw new Error(`GFDI CRC mismatch: expected=0x${hex(expectedCrc, 4)}, actual=0x${hex(actualCrc, 4)}.`);

  const payload = packet.slice(2, length - 2);
  let messageType = readU16(payload, 0);
  if ((messageType & 0x8000) !== 0) messageType = (messageType & 0xff) + 5000;
  const body = payload.slice(2);

  if (messageType !== GarminMessage.RESPONSE) return { kind: "parsed", messageType, raw: body };
  if (body.length < 3) throw new Error("Status packet body is too short.");
  const originalMessageType = readU16(body, 0);
  const status = body[2];
  const rest = body.slice(3);

  if (originalMessageType === GarminMessage.CREATE_FILE) {
    if (status !== Status.ACK) return { kind: "generic", originalMessageType, status };
    if (rest.length < 7) throw new Error("CREATE_FILE status body is too short.");
    return {
      kind: "createFile",
      status,
      createStatus: rest[0],
      fileIndex: readU16(rest, 1),
      dataType: rest[3],
      subtype: rest[4],
      fileNumber: readU16(rest, 5)
    };
  }

  if (originalMessageType === GarminMessage.UPLOAD_REQUEST) {
    if (status !== Status.ACK) return { kind: "generic", originalMessageType, status };
    if (rest.length < 11) throw new Error("UPLOAD_REQUEST status body is too short.");
    return {
      kind: "uploadRequest",
      status,
      uploadStatus: rest[0],
      dataOffset: readU32(rest, 1),
      maxFileSize: readU32(rest, 5),
      crcSeed: readU16(rest, 9)
    };
  }

  if (originalMessageType === GarminMessage.FILE_TRANSFER_DATA) {
    if (status !== Status.ACK) return { kind: "generic", originalMessageType, status };
    if (rest.length < 5) throw new Error("FILE_TRANSFER_DATA status body is too short.");
    return {
      kind: "fileTransferData",
      status,
      transferStatus: rest[0],
      dataOffset: readU32(rest, 1)
    };
  }

  return { kind: "generic", originalMessageType, status };
}

function garminCrc(data, initialCrc = 0) {
  let crc = initialCrc & 0xffff;
  for (const byte of data) {
    crc = (((crc >> 4) & 0x0fff) ^ CRC_CONSTANTS[crc & 0x0f]) ^ CRC_CONSTANTS[byte & 0x0f];
    crc = (((crc >> 4) & 0x0fff) ^ CRC_CONSTANTS[crc & 0x0f]) ^ CRC_CONSTANTS[(byte >> 4) & 0x0f];
  }
  return crc & 0xffff;
}

function cobsEncode(data) {
  const encoded = [0];
  let position = 0;
  let lastByteWasZero = false;
  while (position < data.length) {
    let start = position;
    while (position < data.length && data[position] !== 0) position += 1;
    const zeroIndex = position;
    if (position < data.length && data[position] === 0) {
      position += 1;
      lastByteWasZero = true;
    } else {
      lastByteWasZero = false;
    }
    let payloadSize = zeroIndex - start;
    while (payloadSize >= 0xfe) {
      encoded.push(0xff, ...data.slice(start, start + 0xfe));
      start += 0xfe;
      payloadSize -= 0xfe;
    }
    encoded.push(payloadSize + 1, ...data.slice(start, start + payloadSize));
  }
  if (lastByteWasZero) encoded.push(0x01);
  encoded.push(0);
  return Uint8Array.from(encoded);
}

class CobsDecoder {
  constructor() {
    this.buffer = [];
  }

  feed(data) {
    this.buffer.push(...data);
    const messages = [];
    while (this.buffer.length >= 4) {
      const start = this.buffer.indexOf(0);
      if (start < 0) return messages;
      const end = this.buffer.indexOf(0, start + 1);
      if (end < 0) {
        if (start > 0) this.buffer.splice(0, start);
        return messages;
      }
      if (start > 0) {
        this.buffer.splice(0, start);
        continue;
      }
      const frame = Uint8Array.from(this.buffer.slice(1, end));
      this.buffer.splice(0, end + 1);
      messages.push(cobsDecodeFrame(frame));
    }
    return messages;
  }
}

function cobsDecodeFrame(frame) {
  const decoded = [];
  let index = 0;
  while (index < frame.length) {
    const code = frame[index];
    index += 1;
    if (code === 0) break;
    const payloadSize = code - 1;
    if (index + payloadSize > frame.length) throw new Error("COBS payload runs past frame end.");
    decoded.push(...frame.slice(index, index + payloadSize));
    index += payloadSize;
    if (code !== 0xff && index < frame.length) decoded.push(0);
  }
  return Uint8Array.from(decoded);
}

class ByteWriter {
  constructor() {
    this.out = [];
  }

  u8(value) {
    this.out.push(value & 0xff);
    return this;
  }

  u16(value) {
    this.out.push(value & 0xff, (value >> 8) & 0xff);
    return this;
  }

  u32(value) {
    this.out.push(value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff);
    return this;
  }

  bytes(value) {
    this.out.push(...value);
    return this;
  }

  toBytes() {
    return Uint8Array.from(this.out);
  }
}

function closeAllServices() {
  return Uint8Array.of(0, REQUEST_CLOSE_ALL, GADGETBRIDGE_CLIENT_ID, 0, 0, 0, 0, 0, 0, 0, 0, 0);
}

function registerService(service, reliable) {
  return Uint8Array.of(0, REQUEST_REGISTER_ML, GADGETBRIDGE_CLIENT_ID, 0, 0, 0, 0, 0, 0, 0, service & 0xff, (service >> 8) & 0xff, reliable ? 2 : 0);
}

function dataViewToBytes(value) {
  return new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
}

function readU16(data, offset) {
  return data[offset] | (data[offset + 1] << 8);
}

function readU32(data, offset) {
  return (data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)) >>> 0;
}

function readU64Low(data, offset) {
  const low = readU32(data, offset);
  const high = readU32(data, offset + 4);
  return high === 0 ? low : Number.NaN;
}

function concatBytes(...parts) {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function gfdiUuid(shortValue) {
  return `6a4e${shortValue.toString(16).padStart(4, "0")}-667b-11e3-949a-0800200c9a66`;
}

function getBluetooth() {
  return getBluetoothCandidates()[0]?.bluetooth || null;
}

function getBluetoothCandidates() {
  const mode = apiModeInput?.value || "webble-first";
  const candidates = [];
  if (mode === "webble-only") {
    addBluetoothCandidate(candidates, "navigator.beacio", navigator.beacio);
    addBluetoothCandidate(candidates, "navigator.webble", navigator.webble);
  } else if (mode === "bluetooth-only") {
    addBluetoothCandidate(candidates, "navigator.bluetooth", navigator.bluetooth);
  } else if (mode === "bluetooth-first") {
    addBluetoothCandidate(candidates, "navigator.bluetooth", navigator.bluetooth);
    addBluetoothCandidate(candidates, "navigator.beacio", navigator.beacio);
    addBluetoothCandidate(candidates, "navigator.webble", navigator.webble);
  } else {
    addBluetoothCandidate(candidates, "navigator.beacio", navigator.beacio);
    addBluetoothCandidate(candidates, "navigator.webble", navigator.webble);
    addBluetoothCandidate(candidates, "navigator.bluetooth", navigator.bluetooth);
  }
  return candidates;
}

function addBluetoothCandidate(candidates, label, bluetooth) {
  if (!bluetooth) return;
  if (candidates.some((candidate) => candidate.bluetooth === bluetooth)) return;
  candidates.push({ label, bluetooth });
}

async function appendLateBluetoothCandidates(candidates) {
  for (const delayMs of [0, 250, 750]) {
    if (delayMs) await sleep(delayMs);
    const freshCandidates = getBluetoothCandidates();
    const newCandidates = freshCandidates.filter((fresh) =>
      !candidates.some((candidate) => candidate.bluetooth === fresh.bluetooth || candidate.label === fresh.label)
    );
    if (!newCandidates.length) continue;
    candidates.push(...newCandidates);
    updateBridgeDiagnostics();
    log(`Detected late Bluetooth API after picker handoff: ${newCandidates.map((candidate) => candidate.label).join(", ")}.`);
    return true;
  }
  return false;
}

function bluetoothApiStatusText() {
  const diagnostics = collectBridgeDiagnostics();
  return `navigator.beacio=${diagnostics.navigatorBeacio} navigator.webble=${diagnostics.navigatorWebble} navigator.bluetooth=${diagnostics.navigatorBluetooth} activeApi=${diagnostics.activeApi}`;
}

function updateBridgeDiagnostics() {
  if (!bridgeDiagnosticsText) return;
  bridgeDiagnosticsText.textContent = bridgeDiagnosticsSummary();
}

function logBridgeDiagnostics(prefix) {
  const diagnostics = collectBridgeDiagnostics();
  log(`${prefix}: ${formatDiagnostics(diagnostics)}`);
}

function bridgeDiagnosticsSummary() {
  const diagnostics = collectBridgeDiagnostics();
  const pieces = [
    `active=${diagnostics.activeApi}`,
    `beacio=${diagnostics.navigatorBeacio}`,
    `webble=${diagnostics.navigatorWebble}`,
    `bluetooth=${diagnostics.navigatorBluetooth}`,
    `cdn=${diagnostics.beacioCdnState}`,
    `installed=${diagnostics.beacioCdnInstalled}`,
    `extensionActive=${diagnostics.beacioCdnActive}`
  ];
  return pieces.join(" ");
}

function collectBridgeDiagnostics() {
  const dataset = document.documentElement?.dataset || {};
  const beacioCdnState = safeDiagnosticValue(() => window.BeacioCDN?.getState?.(), "n/a");
  const candidates = getBluetoothCandidates();
  const activeApi = candidates[0]?.label || "none";
  return {
    location: location.origin,
    pageHidden: document.hidden,
    apiMode: apiModeInput?.value || "webble-first",
    serviceMode: serviceModeInput?.value || "transport",
    activeApi,
    candidateApis: candidates.map((candidate) => candidate.label).join(",") || "none",
    navigatorBeacio: Boolean(navigator.beacio),
    navigatorWebble: Boolean(navigator.webble),
    navigatorBluetooth: Boolean(navigator.bluetooth),
    beacioCdnState,
    beacioCdnInstalled: dataset.beacioCdnInstalled || "missing",
    beacioCdnActive: dataset.beacioCdnActive || "missing",
    beacioCdnDatasetState: dataset.beacioCdnState || "missing",
    webkitMessageHandlers: listObjectKeys(window.webkit?.messageHandlers),
    beacioMethods: listBluetoothMethods(navigator.beacio),
    webbleMethods: listBluetoothMethods(navigator.webble),
    bluetoothMethods: listBluetoothMethods(navigator.bluetooth),
    bluetoothRequestDeviceSource: functionSourceKind(navigator.bluetooth?.requestDevice)
  };
}

function formatDiagnostics(diagnostics) {
  return [
    `origin=${diagnostics.location}`,
    `hidden=${diagnostics.pageHidden}`,
    `apiMode=${diagnostics.apiMode}`,
    `accessMode=${diagnostics.serviceMode}`,
    `activeApi=${diagnostics.activeApi}`,
    `candidates=${diagnostics.candidateApis}`,
    `navigator.beacio=${diagnostics.navigatorBeacio}`,
    `navigator.webble=${diagnostics.navigatorWebble}`,
    `navigator.bluetooth=${diagnostics.navigatorBluetooth}`,
    `BeacioCDN.getState=${diagnostics.beacioCdnState}`,
    `dataset.state=${diagnostics.beacioCdnDatasetState}`,
    `dataset.installed=${diagnostics.beacioCdnInstalled}`,
    `dataset.active=${diagnostics.beacioCdnActive}`,
    `webkit.handlers=${diagnostics.webkitMessageHandlers}`,
    `beacio.methods=${diagnostics.beacioMethods}`,
    `webble.methods=${diagnostics.webbleMethods}`,
    `bluetooth.methods=${diagnostics.bluetoothMethods}`,
    `bluetooth.requestDevice=${diagnostics.bluetoothRequestDeviceSource}`
  ].join(" ");
}

function listBluetoothMethods(bluetooth) {
  if (!bluetooth) return "none";
  const methodNames = ["getAvailability", "getDevices", "requestDevice", "requestLEScan", "addEventListener", "removeEventListener"];
  const available = methodNames.filter((name) => typeof bluetooth[name] === "function");
  return available.length ? available.join(",") : "none";
}

function listObjectKeys(value) {
  if (!value) return "none";
  try {
    const keys = Object.keys(value);
    return keys.length ? keys.join(",") : "present-no-enumerable-keys";
  } catch (error) {
    return `unreadable:${messageOf(error)}`;
  }
}

function functionSourceKind(fn) {
  if (typeof fn !== "function") return "missing";
  try {
    const source = Function.prototype.toString.call(fn);
    if (source.includes("[native code]")) return "native";
    if (source.includes("beacio")) return "beacio-wrapper";
    if (source.includes("webble")) return "webble-wrapper";
    return `scripted:${source.slice(0, 80).replace(/\s+/g, " ")}`;
  } catch (error) {
    return `unreadable:${messageOf(error)}`;
  }
}

function safeDiagnosticValue(read, fallback) {
  try {
    const value = read();
    if (value === undefined || value === null) return fallback;
    if (typeof value === "object") return JSON.stringify(value).slice(0, 180);
    return String(value).slice(0, 180);
  } catch (error) {
    return `error:${messageOf(error)}`;
  }
}

function buildDeviceRequestOptions(mode, serviceSet = "full") {
  const transportServices = [
    UUIDS.v2Service,
    UUIDS.v1Service,
    UUIDS.v0Service
  ];
  const optionalServicesByMode = {
    grant: [],
    v2: [UUIDS.v2Service],
    transport: transportServices,
    full: [
      UUIDS.v2Service,
      UUIDS.v1Service,
      UUIDS.v0Service,
      UUIDS.deviceInformation,
      UUIDS.observedFenix6,
      UUIDS.observedGarmin1,
      UUIDS.observedGarmin2
    ]
  };
  const optionalServices = optionalServicesByMode[serviceSet] || transportServices;
  if (mode === "broad") {
    return withOptionalServices({ acceptAllDevices: true }, optionalServices);
  }
  if (mode === "name") {
    return withOptionalServices({
      filters: [
        { name: "fenix 6 Pro" },
        { namePrefix: "fenix 6" },
        { namePrefix: "fenix" }
      ]
    }, optionalServices);
  }
  const garminFilters = serviceSet === "grant" ? [
    { namePrefix: "fenix" },
    { namePrefix: "Fenix" },
    { namePrefix: "Garmin" }
  ] : [
    { services: [UUIDS.observedFenix6] },
    { services: [UUIDS.observedGarmin1] },
    { services: [UUIDS.observedGarmin2] },
    { services: [UUIDS.deviceInformation] },
    { services: [UUIDS.v2Service] },
    { services: [UUIDS.v1Service] },
    { services: [UUIDS.v0Service] },
    { namePrefix: "fenix" },
    { namePrefix: "Fenix" },
    { namePrefix: "Garmin" }
  ];
  return withOptionalServices({
    filters: garminFilters
  }, optionalServices);
}

function withOptionalServices(options, optionalServices) {
  if (optionalServices.length) {
    return { ...options, optionalServices };
  }
  return options;
}

function buildDiagnosticScanFilters() {
  return [
    { services: [UUIDS.observedFenix6] },
    { services: [UUIDS.observedGarmin1] },
    { services: [UUIDS.observedGarmin2] },
    { services: [UUIDS.deviceInformation] },
    { services: [UUIDS.v2Service] },
    { services: [UUIDS.v1Service] },
    { services: [UUIDS.v0Service] }
  ];
}

function describeAdvertisement(event) {
  const uuids = Array.from(event.uuids || []).map((uuid) => String(uuid).toLowerCase());
  const manufacturerIds = event.manufacturerData ? Array.from(event.manufacturerData.keys()) : [];
  const serviceDataIds = event.serviceData ? Array.from(event.serviceData.keys()) : [];
  return {
    id: event.device?.id || `advertisement-${scanAdvertisementCount}`,
    name: event.device?.name || "(no name)",
    rssi: Number.isFinite(event.rssi) ? event.rssi : null,
    uuids,
    manufacturerIds,
    serviceDataIds,
    likelyGarmin: isLikelyGarminAdvertisement(event.device?.name || "", uuids)
  };
}

function formatAdvertisement(item) {
  const rssiText = item.rssi === null ? "rssi=?" : `rssi=${item.rssi}`;
  const marker = item.likelyGarmin ? "GARMIN? " : "";
  const manufacturers = item.manufacturerIds.length ? ` manufacturers=[${item.manufacturerIds.join(", ")}]` : "";
  const serviceData = item.serviceDataIds.length ? ` serviceData=[${item.serviceDataIds.join(", ")}]` : "";
  return `ADV ${marker}${item.name} id=${item.id} ${rssiText} uuids=[${item.uuids.join(", ")}]${manufacturers}${serviceData}`;
}

function isLikelyGarminAdvertisement(name, uuids) {
  const lowerName = name.toLowerCase();
  return lowerName.includes("garmin")
    || lowerName.includes("fenix")
    || uuids.includes(UUIDS.observedFenix6)
    || uuids.includes(UUIDS.observedGarmin1)
    || uuids.includes(UUIDS.observedGarmin2)
    || uuids.includes(UUIDS.v2Service)
    || uuids.includes(UUIDS.v1Service)
    || uuids.includes(UUIDS.v0Service);
}

function requireBluetooth() {
  const bluetooth = getBluetooth();
  if (!bluetooth) throw new Error("iOSWebBLE/Web Bluetooth is not available.");
  return bluetooth;
}

function setBleState(text, ok) {
  bleState.textContent = text;
  bleState.classList.toggle("ok", ok === true);
  bleState.classList.toggle("bad", ok === false);
}

function setStatus(text) {
  statusText.textContent = text;
}

function setProgress(percent, offset, total, stats = null) {
  const clean = Math.max(0, Math.min(100, percent));
  progressBar.value = clean;
  progressText.textContent = `${clean}%`;
  if (total > 0) {
    const parts = [`Uploaded ${formatBytes(offset)} / ${formatBytes(total)}`];
    const metrics = stats ? updateTransferStats(stats, offset) : null;
    if (metrics?.avgBps > 0) {
      parts.push(`avg ${formatRate(metrics.avgBps)}`);
      if (metrics.recentBps > 0) parts.push(`now ${formatRate(metrics.recentBps)}`);
      if (offset < total && metrics.etaSec !== null) parts.push(`ETA ${formatDuration(metrics.etaSec)}`);
    }
    setStatus(parts.join(" - "));
  }
}

function createTransferStats(total) {
  const now = performance.now();
  return {
    total,
    startedAt: now,
    samples: [{ time: now, offset: 0 }]
  };
}

function updateTransferStats(stats, offset) {
  const now = performance.now();
  const cleanOffset = Math.max(0, Math.min(offset, stats.total));
  const samples = stats.samples;
  const last = samples[samples.length - 1];
  if (!last || last.offset !== cleanOffset) {
    samples.push({ time: now, offset: cleanOffset });
  }
  const cutoff = now - 10000;
  while (samples.length > 2 && samples[0].time < cutoff) {
    samples.shift();
  }

  const elapsedSec = Math.max((now - stats.startedAt) / 1000, 0);
  const avgBps = elapsedSec > 0.25 ? cleanOffset / elapsedSec : 0;
  const firstSample = samples[0];
  const recentElapsedSec = Math.max((now - firstSample.time) / 1000, 0);
  const recentBps = recentElapsedSec > 0.25 ? (cleanOffset - firstSample.offset) / recentElapsedSec : 0;
  const etaBps = recentBps > 0 ? recentBps : avgBps;
  const remaining = Math.max(0, stats.total - cleanOffset);
  const etaSec = etaBps > 1 ? remaining / etaBps : null;

  return { avgBps, recentBps, etaSec, elapsedSec };
}

function completedTransferMetrics(stats, total) {
  const elapsedSec = Math.max((performance.now() - stats.startedAt) / 1000, 0);
  const avgBps = elapsedSec > 0 ? total / elapsedSec : 0;
  return { avgBps, elapsedSec };
}

function transferSummaryText(metrics) {
  return `Transfer rate: ${formatRate(metrics.avgBps)} average over ${formatDuration(metrics.elapsedSec)}.`;
}

function updateWatchIdentity(transportTextValue) {
  if (!selectedDevice) {
    watchIdentity.hidden = true;
    watchIdentity.classList.remove("warn", "ok");
    watchMeta.textContent = "No watch selected";
    deviceIdText.textContent = "-";
    transportText.textContent = "Not connected";
    return;
  }
  watchIdentity.hidden = false;
  watchIdentity.classList.toggle("warn", hasTrustedMismatch());
  watchIdentity.classList.toggle("ok", Boolean(trustedDevice) && !hasTrustedMismatch());
  watchMeta.textContent = deviceLabel(selectedDevice);
  deviceIdText.textContent = selectedDevice.id || "Browser did not expose a device id";
  transportText.textContent = `${transportTextValue}. ${trustedWatchStatusText()}`;
}

function setTargetConfirmed(value) {
  targetConfirmed = value;
  confirmTargetInput.checked = value;
}

function rememberSelectedWatch() {
  if (!selectedDevice?.id) {
    showError("Cannot remember watch", new Error("This browser did not expose a stable device id."));
    return;
  }
  trustedDevice = {
    id: selectedDevice.id,
    label: deviceLabel(selectedDevice),
    savedAt: new Date().toISOString()
  };
  saveTrustedDevice(trustedDevice);
  setTargetConfirmed(false);
  updateWatchIdentity(connection ? `Connected using Garmin ${connection.kind}` : "Not connected");
  updateTrustedWatchUi();
  setStatus("Trusted watch saved. Confirm target watch to send.");
  log(`Trusted watch saved: ${trustedDevice.label}`);
  updateButtons();
}

function clearTrustedWatch() {
  trustedDevice = null;
  saveTrustedDevice(null);
  setTargetConfirmed(false);
  updateWatchIdentity(connection ? `Connected using Garmin ${connection.kind}` : "Not connected");
  updateTrustedWatchUi();
  setStatus("Trusted watch cleared.");
  log("Trusted watch cleared.");
  updateButtons();
}

function updateTrustedWatchUi() {
  if (!trustedDevice) {
    trustedWatchText.textContent = "None saved";
  } else {
    trustedWatchText.textContent = trustedDevice.label || trustedDevice.id;
  }
  clearWatchButton.disabled = isBusy || !trustedDevice;
}

function hasTrustedMismatch() {
  if (!trustedDevice) return false;
  if (!selectedDevice?.id) return true;
  return selectedDevice.id !== trustedDevice.id;
}

function trustedWatchStatusText() {
  if (!trustedDevice) return "No trusted watch saved.";
  if (!selectedDevice?.id) return "Trusted watch cannot be checked because no browser device id is available.";
  return selectedDevice.id === trustedDevice.id ? "Matches trusted watch." : "Does not match trusted watch.";
}

function loadTrustedDevice() {
  try {
    const raw = localStorage.getItem(TRUSTED_DEVICE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveTrustedDevice(device) {
  try {
    if (device) localStorage.setItem(TRUSTED_DEVICE_KEY, JSON.stringify(device));
    else localStorage.removeItem(TRUSTED_DEVICE_KEY);
  } catch (error) {
    log(`Could not save trusted watch: ${messageOf(error)}`);
  }
}

function loadGithubRepoSetting() {
  try {
    const raw = localStorage.getItem(GITHUB_REPO_KEY);
    return raw ? normalizeGitHubRepo(raw) : DEFAULT_GITHUB_REPO;
  } catch {
    return DEFAULT_GITHUB_REPO;
  }
}

function saveGithubRepoSetting(repo) {
  try {
    localStorage.setItem(GITHUB_REPO_KEY, normalizeGitHubRepo(repo));
  } catch (error) {
    log(`Could not save GitHub repo setting: ${messageOf(error)}`);
  }
}

function selectedGithubPrgAsset() {
  const selectedId = githubPrgInput?.value;
  return selectedId ? githubPrgAssets.find((asset) => asset.id === selectedId) || null : null;
}

function autoTuneSettings() {
  const best = bestTuningResult();
  if (best) {
    applyTuningSettings(best);
    const message = `Auto Tune applied best recorded settings: GFDI ${best.maxPacketSize}, BLE ${best.fragmentSize}, pipeline ${best.pipelineWindow}, delay ${best.writeDelayMs} ms (${formatRate(best.avgBps)}).`;
    setStatus(message);
    log(message);
    return;
  }
  const preset = shouldUseMlrTuning() ? FAST_FENIX6_MLR_TUNING : FAST_FENIX6_TUNING;
  applyTuningSettings(preset);
  const message = `Auto Tune applied ${preset.label}: GFDI ${preset.maxPacketSize}, BLE ${preset.fragmentSize}, pipeline ${preset.pipelineWindow}, delay ${preset.writeDelayMs} ms.`;
  setStatus(message);
  log(`${message} Successful uploads will update the best setting automatically.`);
}

function onReliableMlrChanged() {
  if (!reliableMlrInput?.checked) return;
  const current = currentUploadSettings();
  if (current.maxPacketSize < FAST_FENIX6_MLR_TUNING.maxPacketSize || current.pipelineWindow < FAST_FENIX6_MLR_TUNING.pipelineWindow) {
    applyTuningSettings({
      ...current,
      maxPacketSize: Math.max(current.maxPacketSize, FAST_FENIX6_MLR_TUNING.maxPacketSize),
      pipelineWindow: Math.max(current.pipelineWindow, FAST_FENIX6_MLR_TUNING.pipelineWindow)
    });
    log(`MLR selected; applied observed fast starting point: GFDI ${packetSizeInput.value}, BLE ${fragmentSizeInput.value}, pipeline ${pipelineWindowInput.value}, delay ${writeDelayInput.value} ms.`);
  }
}

function rememberUploadRequest(benchmark, failedBenchmarkProfiles = new Set()) {
  lastUploadRequest = {
    benchmark: Boolean(benchmark),
    failedBenchmarkProfiles: Array.from(failedBenchmarkProfiles)
  };
}

function setRetryAvailable(value) {
  retryAvailable = Boolean(value && lastUploadRequest);
  updateButtons();
}

function clearRetryState() {
  retryAvailable = false;
  lastUploadRequest = null;
  if (retryButton) retryButton.textContent = "Retry";
  updateButtons();
}

function currentUploadSettings() {
  return {
    maxPacketSize: readGfdiPacketSize(),
    fragmentSize: readBleFragmentSize(),
    pipelineWindow: readPipelineWindow(),
    writeDelayMs: readWriteDelayMs(),
    label: "current"
  };
}

function applyTuningSettings(settings) {
  packetSizeInput.value = String(settings.maxPacketSize);
  fragmentSizeInput.value = String(settings.fragmentSize);
  pipelineWindowInput.value = String(settings.pipelineWindow);
  writeDelayInput.value = String(settings.writeDelayMs);
}

function applyTransportSettings(transport, settings) {
  if (!transport) return;
  transport.writeFragmentSize = clampNumber(settings.fragmentSize, SAFE_BLE_FRAGMENT_SIZE, MAX_BLE_FRAGMENT_SIZE, SAFE_BLE_FRAGMENT_SIZE);
  transport.writeDelayMs = clampNumber(settings.writeDelayMs, 0, 25, 0);
}

function buildBenchmarkProfiles(baseSettings, fileSize, failedProfiles = new Set()) {
  const fragmentProfiles = buildFragmentProbeProfiles(baseSettings);
  const largeGfdiProfiles = shouldProbeLargeGfdi(baseSettings) ? [
    { maxPacketSize: 1500, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 8, writeDelayMs: 0, label: "MLR probe 1500/20/8/0" },
    { maxPacketSize: 2048, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 8, writeDelayMs: 0, label: "MLR probe 2048/20/8/0" },
    { maxPacketSize: 3072, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 8, writeDelayMs: 0, label: "MLR probe 3072/20/8/0" },
    { maxPacketSize: 4096, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 8, writeDelayMs: 0, label: "MLR probe 4096/20/8/0" },
    { maxPacketSize: 6144, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 8, writeDelayMs: 0, label: "MLR probe 6144/20/8/0" },
    { maxPacketSize: 8192, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 8, writeDelayMs: 0, label: "MLR probe 8192/20/8/0" }
  ] : [];
  const stableProfiles = [
    { maxPacketSize: 375, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 1, writeDelayMs: 0, label: "375/20/1/0" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 1, writeDelayMs: 0, label: "400/20/1/0" },
    { maxPacketSize: 375, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 2, writeDelayMs: 0, label: "375/20/2/0" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 2, writeDelayMs: 0, label: "400/20/2/0" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 2, writeDelayMs: 2, label: "400/20/2/2" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 2, writeDelayMs: 5, label: "400/20/2/5" }
  ];
  const riskyProfiles = riskyPipelineInput?.checked ? [
    { maxPacketSize: 1500, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 10, writeDelayMs: 0, label: "risky MLR 1500/20/10/0" },
    { maxPacketSize: 1500, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 12, writeDelayMs: 0, label: "risky MLR 1500/20/12/0" },
    { maxPacketSize: 1500, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 16, writeDelayMs: 0, label: "risky MLR 1500/20/16/0" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 3, writeDelayMs: 5, label: "risky 400/20/3/5" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 3, writeDelayMs: 10, label: "risky 400/20/3/10" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 3, writeDelayMs: 15, label: "risky 400/20/3/15" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 4, writeDelayMs: 10, label: "risky 400/20/4/10" },
    { maxPacketSize: 400, fragmentSize: SAFE_BLE_FRAGMENT_SIZE, pipelineWindow: 4, writeDelayMs: 15, label: "risky 400/20/4/15" }
  ] : [];
  const profiles = riskyPipelineInput?.checked
    ? [...fragmentProfiles, ...largeGfdiProfiles, ...riskyProfiles, FAST_FENIX6_TUNING, ...stableProfiles, baseSettings]
    : [...fragmentProfiles, ...largeGfdiProfiles, FAST_FENIX6_TUNING, ...stableProfiles, baseSettings]
  return uniqueBenchmarkProfiles(profiles
    .filter((profile) => fileSize >= Math.max(1024, profile.maxPacketSize * profile.pipelineWindow))
    .filter((profile) => !failedProfiles.has(benchmarkProfileKey(profile))));
}

function buildFragmentProbeProfiles(baseSettings) {
  const selectedFragment = clampNumber(baseSettings.fragmentSize, SAFE_BLE_FRAGMENT_SIZE, MAX_BLE_FRAGMENT_SIZE, SAFE_BLE_FRAGMENT_SIZE);
  if (selectedFragment <= SAFE_BLE_FRAGMENT_SIZE) return [];
  const sizes = uniqueNumbers([
    selectedFragment,
    MAX_BLE_FRAGMENT_SIZE,
    160,
    120,
    80,
    60,
    40,
    SAFE_BLE_FRAGMENT_SIZE
  ]).filter((size) => size >= SAFE_BLE_FRAGMENT_SIZE && size <= MAX_BLE_FRAGMENT_SIZE);
  return sizes.map((fragmentSize) => ({
    ...baseSettings,
    fragmentSize,
    label: `fragment probe ${baseSettings.maxPacketSize}/${fragmentSize}/${baseSettings.pipelineWindow}/${baseSettings.writeDelayMs}`
  }));
}

function shouldProbeLargeGfdi(baseSettings) {
  return shouldUseMlrTuning()
    || Number(baseSettings.maxPacketSize) >= LARGE_GFDI_PACKET_SIZE;
}

function shouldUseMlrTuning() {
  return Boolean(reliableMlrInput?.checked)
    || String(connection?.kind || "").includes("reliable MLR");
}

function benchmarkProfileKey(profile) {
  return `${profile.maxPacketSize}/${profile.fragmentSize}/${profile.pipelineWindow}/${profile.writeDelayMs}`;
}

function uniqueNumbers(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const number = Number(value);
    if (!Number.isFinite(number) || seen.has(number)) continue;
    seen.add(number);
    result.push(number);
  }
  return result;
}

function uniqueBenchmarkProfiles(profiles) {
  const seen = new Set();
  const unique = [];
  for (const profile of profiles) {
    const normalized = {
      maxPacketSize: clampNumber(profile.maxPacketSize, 64, MAX_EXPERIMENTAL_GFDI_PACKET_SIZE, SAFE_GFDI_PACKET_SIZE),
      fragmentSize: clampNumber(profile.fragmentSize, SAFE_BLE_FRAGMENT_SIZE, MAX_BLE_FRAGMENT_SIZE, SAFE_BLE_FRAGMENT_SIZE),
      pipelineWindow: clampNumber(profile.pipelineWindow, 1, MAX_PIPELINE_WINDOW, 1),
      writeDelayMs: clampNumber(profile.writeDelayMs, 0, 25, 0),
      label: profile.label || `${profile.maxPacketSize}/${profile.fragmentSize}/${profile.pipelineWindow}/${profile.writeDelayMs}`
    };
    const key = benchmarkProfileKey(normalized);
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push({ ...normalized, label: key === `${normalized.label}` ? normalized.label : `${normalized.label} (${key})` });
  }
  return unique;
}

function recordTuningResult(result) {
  try {
    const history = readTuningHistory();
    history.push({
      maxPacketSize: result.maxPacketSize,
      fragmentSize: result.fragmentSize,
      pipelineWindow: result.pipelineWindow,
      writeDelayMs: result.writeDelayMs,
      avgBps: result.avgBps,
      elapsedSec: result.elapsedSec,
      fileSize: result.fileSize,
      transportKind: result.transportKind,
      savedAt: new Date().toISOString()
    });
    const cleaned = history
      .filter(isValidTuningResult)
      .sort((left, right) => (right.avgBps || 0) - (left.avgBps || 0))
      .slice(0, MAX_TUNING_HISTORY);
    localStorage.setItem(TUNING_HISTORY_KEY, JSON.stringify(cleaned));
    log(`Saved tuning result: GFDI ${result.maxPacketSize}, BLE ${result.fragmentSize}, pipeline ${result.pipelineWindow}, delay ${result.writeDelayMs} ms, ${formatRate(result.avgBps)}.`);
  } catch (error) {
    log(`Could not save tuning result: ${messageOf(error)}`);
  }
}

function bestTuningResult() {
  return readTuningHistory()
    .filter(isValidTuningResult)
    .sort((left, right) => (right.avgBps || 0) - (left.avgBps || 0))[0] || null;
}

function readTuningHistory() {
  try {
    const raw = localStorage.getItem(TUNING_HISTORY_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    log(`Could not read tuning history: ${messageOf(error)}`);
    return [];
  }
}

function isValidTuningResult(value) {
  return value
    && Number.isFinite(value.maxPacketSize)
    && Number.isFinite(value.fragmentSize)
    && Number.isFinite(value.pipelineWindow)
    && Number.isFinite(value.writeDelayMs)
    && Number.isFinite(value.avgBps)
    && value.maxPacketSize >= 64
    && value.maxPacketSize <= MAX_EXPERIMENTAL_GFDI_PACKET_SIZE
    && value.fragmentSize >= SAFE_BLE_FRAGMENT_SIZE
    && value.fragmentSize <= MAX_BLE_FRAGMENT_SIZE
    && value.pipelineWindow >= 1
    && value.pipelineWindow <= MAX_PIPELINE_WINDOW
    && value.writeDelayMs >= 0
    && value.writeDelayMs <= 25
    && value.avgBps > 0;
}

function normalizeGitHubRepo(value) {
  let text = String(value || "").trim();
  if (!text) throw new Error("Enter a GitHub repo as owner/name.");
  text = text.replace(/^https?:\/\/github\.com\//i, "");
  text = text.replace(/^github\.com\//i, "");
  text = text.replace(/\.git$/i, "");
  text = text.replace(/^\/+|\/+$/g, "");
  const parts = text.split("/").filter(Boolean);
  if (parts.length < 2) throw new Error("Enter a GitHub repo as owner/name.");
  const repo = `${parts[0]}/${parts[1]}`;
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
    throw new Error("GitHub repo must look like owner/name.");
  }
  return repo;
}

function supportsSavedPrgLibrary() {
  return typeof indexedDB !== "undefined";
}

function selectedSavedPrgRecord() {
  const selectedId = savedPrgInput?.value;
  return selectedId ? savedPrgRecords.find((record) => record.id === selectedId) || null : null;
}

function savedPrgId(name, size) {
  return `${name}::${size}`;
}

function savedRecordToBytes(record) {
  const data = record?.data;
  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
  throw new Error("Saved PRG data is not readable.");
}

async function putSavedPrg(record) {
  const db = await openSavedPrgDb();
  await runSavedPrgTransaction(db, "readwrite", (store) => store.put(record));
  db.close();
}

async function getSavedPrg(id) {
  const db = await openSavedPrgDb();
  try {
    return await requestToPromise(db.transaction(SAVED_PRG_STORE, "readonly").objectStore(SAVED_PRG_STORE).get(id));
  } finally {
    db.close();
  }
}

async function getAllSavedPrgs() {
  const db = await openSavedPrgDb();
  try {
    return await requestToPromise(db.transaction(SAVED_PRG_STORE, "readonly").objectStore(SAVED_PRG_STORE).getAll());
  } finally {
    db.close();
  }
}

async function deleteSavedPrgRecord(id) {
  const db = await openSavedPrgDb();
  await runSavedPrgTransaction(db, "readwrite", (store) => store.delete(id));
  db.close();
}

async function trimSavedPrgLibrary() {
  const records = await getAllSavedPrgs();
  const oldRecords = records
    .sort((left, right) => String(right.savedAt).localeCompare(String(left.savedAt)))
    .slice(MAX_SAVED_PRGS);
  for (const record of oldRecords) {
    await deleteSavedPrgRecord(record.id);
    log(`Removed older saved PRG: ${record.name}`);
  }
}

function openSavedPrgDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(SAVED_PRG_DB_NAME, SAVED_PRG_DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(SAVED_PRG_STORE)) {
        db.createObjectStore(SAVED_PRG_STORE, { keyPath: "id" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("Could not open saved PRG database."));
    request.onblocked = () => reject(new Error("Saved PRG database is blocked by another tab."));
  });
}

function runSavedPrgTransaction(db, mode, action) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(SAVED_PRG_STORE, mode);
    const store = transaction.objectStore(SAVED_PRG_STORE);
    action(store);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error || new Error("Saved PRG transaction failed."));
    transaction.onabort = () => reject(transaction.error || new Error("Saved PRG transaction aborted."));
  });
}

function requestToPromise(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("Saved PRG request failed."));
  });
}

function deviceLabel(device) {
  const name = device?.name || "(no name)";
  const id = device?.id ? ` - ${device.id}` : "";
  return `${name}${id}`;
}

function updateButtons() {
  const hasGithubPrg = Boolean(selectedGithubPrgAsset());
  refreshGithubPrgsButton.disabled = isBusy || isScanning;
  loadGithubPrgButton.disabled = isBusy || isScanning || !hasGithubPrg;
  const hasSavedPrg = Boolean(selectedSavedPrgRecord());
  loadSavedPrgButton.disabled = isBusy || isScanning || !hasSavedPrg;
  deleteSavedPrgButton.disabled = isBusy || isScanning || !hasSavedPrg;
  chooseWatchButton.disabled = isBusy || isScanning || !getBluetooth();
  connectButton.disabled = isBusy || isScanning || !selectedDevice;
  scanButton.disabled = isBusy || isScanning || !getBluetooth();
  stopScanButton.disabled = !isScanning;
  if (wifiProbeButton) wifiProbeButton.disabled = isBusy || isScanning || isWifiProbing;
  if (wifiStopButton) wifiStopButton.disabled = !isWifiProbing;
  rememberWatchButton.disabled = isBusy || isScanning || !connection || !selectedDevice?.id;
  clearWatchButton.disabled = isBusy || isScanning || !trustedDevice;
  confirmTargetInput.disabled = isBusy || isScanning || !connection || hasTrustedMismatch();
  sendButton.disabled = isBusy || isScanning || !selectedFile || !connection || !targetConfirmed || hasTrustedMismatch();
  if (benchmarkSendButton) benchmarkSendButton.disabled = sendButton.disabled;
  if (retryButton) {
    const canRetry = isUploading || retryAvailable;
    retryButton.disabled = isScanning || !canRetry || !lastUploadRequest || !selectedFile || !selectedDevice || hasTrustedMismatch() || (isBusy && !isUploading);
    retryButton.textContent = isUploading
      ? "Stop + Retry"
      : (lastUploadRequest ? (lastUploadRequest.benchmark ? "Retry Benchmark" : "Retry Send") : "Retry");
  }
  if (stopUploadButton) stopUploadButton.disabled = !isUploading;
  if (autoTuneButton) autoTuneButton.disabled = isBusy || isScanning;
}

function setBusy(value) {
  isBusy = value;
  updateButtons();
}

function setScanning(value) {
  isScanning = value;
  updateButtons();
}

function readNumber(input, fallback) {
  const value = Number(input.value);
  return Number.isFinite(value) ? value : fallback;
}

function readGfdiPacketSize() {
  const value = clampNumber(packetSizeInput.value, 64, MAX_EXPERIMENTAL_GFDI_PACKET_SIZE, SAFE_GFDI_PACKET_SIZE);
  packetSizeInput.value = String(value);
  return value;
}

function readBleFragmentSize() {
  const value = clampNumber(fragmentSizeInput.value, SAFE_BLE_FRAGMENT_SIZE, MAX_BLE_FRAGMENT_SIZE, SAFE_BLE_FRAGMENT_SIZE);
  fragmentSizeInput.value = String(value);
  return value;
}

function readPipelineWindow() {
  if (!pipelineWindowInput) return 1;
  const value = clampNumber(pipelineWindowInput.value, 1, MAX_PIPELINE_WINDOW, 1);
  pipelineWindowInput.value = String(value);
  return value;
}

function readWriteDelayMs() {
  const value = clampNumber(writeDelayInput.value, 0, 25, 0);
  writeDelayInput.value = String(value);
  return value;
}

function clampNumber(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, number));
}

function formatBytes(size) {
  if (!Number.isFinite(size)) return "? bytes";
  if (size < 1024) return `${size} bytes`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / 1024 / 1024).toFixed(2)} MB`;
}

function formatRate(bytesPerSecond) {
  if (!Number.isFinite(bytesPerSecond) || bytesPerSecond <= 0) return "? KB/s";
  if (bytesPerSecond < 1024 * 1024) return `${(bytesPerSecond / 1024).toFixed(1)} KB/s`;
  return `${(bytesPerSecond / 1024 / 1024).toFixed(2)} MB/s`;
}

function formatDuration(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return "?";
  const totalSeconds = Math.round(seconds);
  const minutes = Math.floor(totalSeconds / 60);
  const remainingSeconds = totalSeconds % 60;
  if (minutes <= 0) return `${remainingSeconds}s`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  if (hours <= 0) return `${minutes}m ${remainingSeconds}s`;
  return `${hours}h ${remainingMinutes}m`;
}

function selectedPrgMetaText(name, size, source = "") {
  const suffix = source ? ` (${source})` : "";
  const warning = largePrgWarning(size);
  return `${name} - ${size.toLocaleString()} bytes${suffix}${warning ? ` - ${warning}` : ""}`;
}

function largePrgWarning(size) {
  return size >= LARGE_PRG_WARNING_SIZE
    ? "large for fenix 6; the watch may reject the PRG slot"
    : "";
}

function logLargePrgWarning(name, size) {
  const warning = largePrgWarning(size);
  if (warning) {
    log(`Warning: ${name} is ${formatBytes(size)}; ${warning}.`);
  }
}

function createStatusName(value) {
  for (const [name, code] of Object.entries(CreateStatus)) {
    if (code === value) return name;
  }
  return `UNKNOWN_${value}`;
}

function describeCreateFileFailure(createStatus, fileSize) {
  const statusName = createStatusName(createStatus.createStatus);
  const raw = JSON.stringify(createStatus);
  if (createStatus.status !== Status.ACK) {
    return `Watch did not ACK PRG file creation. Raw status: ${raw}`;
  }
  if (createStatus.createStatus === CreateStatus.NO_SLOTS) {
    return `Watch rejected PRG file creation: ${statusName}. Remove an unused Connect IQ app slot, then try again. Raw status: ${raw}`;
  }
  if (createStatus.createStatus === CreateStatus.NO_SPACE || createStatus.createStatus === CreateStatus.NO_SPACE_FOR_TYPE) {
    return `Watch rejected PRG file creation: ${statusName} for ${formatBytes(fileSize)}. The PRG is probably too large for the fenix 6 PRG staging/app area, or storage for this file type is full. Try a smaller PRG or free watch storage. Raw status: ${raw}`;
  }
  if (createStatus.createStatus === CreateStatus.UNSUPPORTED) {
    return `Watch rejected PRG file creation: ${statusName}. This firmware did not accept PRG 255/17 over this path. Raw status: ${raw}`;
  }
  if (createStatus.createStatus === CreateStatus.DUPLICATE) {
    return `Watch rejected PRG file creation: ${statusName}. The same PRG may already be staged. Let Garmin Connect sync, then retry if needed. Raw status: ${raw}`;
  }
  return `Watch rejected PRG file creation: ${statusName}. Raw status: ${raw}`;
}

function showError(prefix, error) {
  const message = `${prefix}: ${messageOf(error)}`;
  setStatus(message);
  log(message);
}

function messageOf(error) {
  return error instanceof Error ? error.message : String(error);
}

function isOriginPickerRejection(error) {
  return messageOf(error).includes("was not offered to this origin via the device picker");
}

function isHandleMessageError(error) {
  return messageOf(error).includes("handleMessage");
}

function log(message) {
  const stamp = new Date().toLocaleTimeString();
  logEl.textContent += `${stamp}  ${message}\n`;
  logEl.scrollTop = logEl.scrollHeight;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function withTimeout(promise, timeoutMs, message, signal) {
  throwIfAborted(signal);
  let timeoutId = null;
  let abortHandler = null;
  const timeout = new Promise((_, reject) => {
    timeoutId = setTimeout(() => reject(new Error(message)), timeoutMs);
  });
  const candidates = [promise, timeout];
  if (signal) {
    candidates.push(new Promise((_, reject) => {
      abortHandler = () => reject(abortError());
      signal.addEventListener("abort", abortHandler, { once: true });
    }));
  }
  return Promise.race(candidates).finally(() => {
    if (timeoutId !== null) clearTimeout(timeoutId);
    if (abortHandler) signal?.removeEventListener?.("abort", abortHandler);
  });
}

function throwIfAborted(signal) {
  if (signal?.aborted) throw abortError();
}

function abortError() {
  const error = new Error("Upload was stopped.");
  error.name = "AbortError";
  return error;
}

function isAbortError(error) {
  return error?.name === "AbortError";
}

function hex(value, width) {
  return value.toString(16).padStart(width, "0");
}

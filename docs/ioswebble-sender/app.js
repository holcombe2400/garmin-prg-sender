const PRG_MAGIC = [0xd0, 0x00, 0xd0];
const PRG_TYPE = 255;
const PRG_SUBTYPE = 17;
const MAX_EXPECTED_PRG_SIZE = 10 * 1024 * 1024;
const TRUSTED_DEVICE_KEY = "garminPrgSender.trustedDevice";
const SAVED_PRG_DB_NAME = "garminPrgSender.savedPrgs";
const SAVED_PRG_DB_VERSION = 1;
const SAVED_PRG_STORE = "files";
const MAX_SAVED_PRGS = 12;

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
  OK: 0
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
const progressBar = document.querySelector("#progressBar");
const progressText = document.querySelector("#progressText");
const statusText = document.querySelector("#statusText");
const logEl = document.querySelector("#log");
const detailsButton = document.querySelector("#detailsButton");
const packetSizeInput = document.querySelector("#packetSizeInput");
const fragmentSizeInput = document.querySelector("#fragmentSizeInput");
const writeDelayInput = document.querySelector("#writeDelayInput");
const apiModeInput = document.querySelector("#apiModeInput");
const pickerModeInput = document.querySelector("#pickerModeInput");
const serviceModeInput = document.querySelector("#serviceModeInput");
const bridgeDiagnosticsText = document.querySelector("#bridgeDiagnosticsText");
const bridgeDiagnosticsButton = document.querySelector("#bridgeDiagnosticsButton");
const scanButton = document.querySelector("#scanButton");
const stopScanButton = document.querySelector("#stopScanButton");
const scanSummary = document.querySelector("#scanSummary");

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

init().catch((error) => showError("Startup failed", error));

async function init() {
  applyRuntimeDefaults();
  detailsButton.addEventListener("click", () => {
    logEl.hidden = !logEl.hidden;
    detailsButton.textContent = logEl.hidden ? "Show Details" : "Hide Details";
  });
  fileInput.addEventListener("change", onFileSelected);
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
  rememberWatchButton.addEventListener("click", rememberSelectedWatch);
  clearWatchButton.addEventListener("click", clearTrustedWatch);
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
  sendButton.addEventListener("click", sendPrg);
  updateTrustedWatchUi();
  await refreshSavedPrgLibrary();
  updateBridgeDiagnostics();
  logBridgeDiagnostics("Startup bridge diagnostics");
  window.setTimeout(updateBridgeDiagnostics, 500);
  window.setTimeout(updateBridgeDiagnostics, 1500);
  window.addEventListener("focus", updateBridgeDiagnostics);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) updateBridgeDiagnostics();
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
    fileMeta.textContent = `${file.name} - ${data.length.toLocaleString()} bytes`;
    await savePrgToLibrary(file.name, data, file.lastModified || Date.now());
    setStatus("PRG loaded and saved locally.");
    log(`Selected PRG: ${file.name} (${data.length} bytes)`);
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
    fileMeta.textContent = `${record.name} - ${data.length.toLocaleString()} bytes (saved)`;
    setStatus("Saved PRG loaded.");
    log(`Loaded saved PRG: ${record.name} (${data.length} bytes)`);
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

async function connectWatch() {
  if (!selectedDevice) return;
  try {
    setBusy(true);
    setStatus("Connecting...");
    connection = await connectGarminTransport(selectedDevice, {
      writeFragmentSize: readNumber(fragmentSizeInput, 20),
      writeDelayMs: readNumber(writeDelayInput, 0)
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

async function sendPrg() {
  if (!selectedFile || !connection || !targetConfirmed || hasTrustedMismatch()) return;
  try {
    setBusy(true);
    setProgress(0, 0, selectedFile.size);
    await uploadPrg(selectedFile.data, connection, {
      maxPacketSize: readNumber(packetSizeInput, 375),
      timeoutMs: 30000,
      maxRetries: 5,
      onProgress: ({ offset, total }) => setProgress(Math.floor((100 * offset) / total), offset, total)
    });
    setProgress(100, selectedFile.size, selectedFile.size);
    setStatus("Upload complete. Let Garmin Connect reconnect to register the app.");
    log("Upload complete. Garmin Connect must perform the registration pass.");
  } catch (error) {
    showError("Upload failed", error);
  } finally {
    setBusy(false);
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
    this.writeFragmentSize = clampNumber(options.writeFragmentSize, 20, 180, 20);
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

  receiveGfdi(timeoutMs) {
    const ready = this.messages.shift();
    if (ready) return Promise.resolve(ready);
    return new Promise((resolve, reject) => {
      const waiter = (message) => {
        clearTimeout(timeout);
        resolve(message);
      };
      const timeout = setTimeout(() => {
        const index = this.waiters.indexOf(waiter);
        if (index >= 0) this.waiters.splice(index, 1);
        reject(new Error(`Timed out waiting for GFDI response after ${timeoutMs}ms`));
      }, timeoutMs);
      this.waiters.push(waiter);
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

  async sendGfdi(packet) {
    const encoded = cobsEncode(packet);
    for (let offset = 0; offset < encoded.length; offset += this.writeFragmentSize) {
      await this.writeRaw(encoded.slice(offset, offset + this.writeFragmentSize));
    }
  }
}

class V2Transport extends BaseTransport {
  constructor(receive, send, options) {
    super(receive, send, "v2", options);
    this.gfdiHandle = null;
  }

  async initialize() {
    await super.initialize();
    await this.writeRaw(closeAllServices());
    await this.waitForGfdiHandle(15000);
  }

  onNotify(value) {
    if (!value.length) return;
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

  async sendGfdi(packet) {
    if (this.gfdiHandle === null) throw new Error("v2 GFDI handle is not registered.");
    const encoded = cobsEncode(packet);
    const fragmentSize = Math.max(1, this.writeFragmentSize - 1);
    for (let offset = 0; offset < encoded.length; offset += fragmentSize) {
      const fragment = encoded.slice(offset, offset + fragmentSize);
      await this.writeRaw(concatBytes(Uint8Array.of(this.gfdiHandle), fragment));
    }
  }

  handleManagement(data) {
    if (data.length < 9) return;
    const requestType = data[0];
    const clientId = readU64Low(data, 1);
    if (clientId !== GADGETBRIDGE_CLIENT_ID) return;
    if (requestType === REQUEST_CLOSE_ALL_RESP) {
      this.writeRaw(registerService(SERVICE_GFDI, false)).catch((error) => {
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
      if (reliable) {
        this.handleReject?.(new Error("Watch registered GFDI as reliable MLR; this sender only implements unreliable ML."));
        return;
      }
      this.gfdiHandle = handle;
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

async function uploadPrg(data, transport, options) {
  validatePrg(data);
  const timeoutMs = options.timeoutMs ?? 30000;
  const maxRetries = options.maxRetries ?? 5;
  const maxPacketSize = clampNumber(options.maxPacketSize, 64, 375, 375);

  log("Sending SYNC_READY.");
  await sendSystemEvent(transport, buildSyncReady(), timeoutMs);

  log(`Creating PRG file slot (${data.length} bytes).`);
  await transport.sendGfdi(buildCreateFile(data.length));
  const createStatus = await receiveKind(transport, "createFile", timeoutMs);
  if (createStatus.status !== Status.ACK || createStatus.createStatus !== CreateStatus.OK) {
    throw new Error(`Create file failed: ${JSON.stringify(createStatus)}`);
  }
  if (createStatus.dataType !== PRG_TYPE || createStatus.subtype !== PRG_SUBTYPE) {
    throw new Error(`Watch created unexpected file type ${createStatus.dataType}/${createStatus.subtype}`);
  }
  options.onProgress?.({ offset: 0, total: data.length });

  log(`Starting upload to file index ${createStatus.fileIndex}.`);
  await transport.sendGfdi(buildUploadRequest(createStatus.fileIndex, data.length));
  const uploadStatus = await receiveKind(transport, "uploadRequest", timeoutMs);
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

  let retries = 0;
  while (true) {
    const chunk = chunker.nextChunk();
    if (!chunk) break;

    await transport.sendGfdi(buildFileTransferData(chunk.data, chunk.offset, chunk.runningCrc));
    const transferStatus = await receiveKind(transport, "fileTransferData", timeoutMs);
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

  log("Sending SYNC_COMPLETE.");
  await sendSystemEvent(transport, buildSyncComplete(), timeoutMs);
  await sleep(2000);
}

async function sendSystemEvent(transport, packet, timeoutMs) {
  await transport.sendGfdi(packet);
  const status = await receiveGenericStatus(transport, GarminMessage.SYSTEM_EVENT, timeoutMs);
  if (status.status !== Status.ACK) {
    throw new Error(`System event failed: ${JSON.stringify(status)}`);
  }
}

async function receiveGenericStatus(transport, originalMessageType, timeoutMs) {
  while (true) {
    const message = parseGfdi(await transport.receiveGfdi(timeoutMs));
    if (message.kind === "generic" && message.originalMessageType === originalMessageType) return message;
  }
}

async function receiveKind(transport, kind, timeoutMs) {
  while (true) {
    const message = parseGfdi(await transport.receiveGfdi(timeoutMs));
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
    this.maxPayloadSize = maxPacketSize - 13;
    this.offset = initialOffset;
    this.runningCrc = initialCrc === undefined ? garminCrc(data.slice(0, initialOffset)) : initialCrc & 0xffff;
  }

  seek(offset, runningCrc = undefined) {
    if (offset < 0 || offset > this.data.length) throw new Error("Offset is outside the upload data.");
    this.offset = offset;
    this.runningCrc = runningCrc === undefined ? garminCrc(this.data.slice(0, offset)) : runningCrc & 0xffff;
  }

  nextChunk() {
    if (this.offset >= this.data.length) return null;
    const data = this.data.slice(this.offset, this.offset + this.maxPayloadSize);
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

function setProgress(percent, offset, total) {
  const clean = Math.max(0, Math.min(100, percent));
  progressBar.value = clean;
  progressText.textContent = `${clean}%`;
  if (total > 0) setStatus(`Uploaded ${offset.toLocaleString()} / ${total.toLocaleString()} bytes`);
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
  const hasSavedPrg = Boolean(selectedSavedPrgRecord());
  loadSavedPrgButton.disabled = isBusy || isScanning || !hasSavedPrg;
  deleteSavedPrgButton.disabled = isBusy || isScanning || !hasSavedPrg;
  chooseWatchButton.disabled = isBusy || isScanning || !getBluetooth();
  connectButton.disabled = isBusy || isScanning || !selectedDevice;
  scanButton.disabled = isBusy || isScanning || !getBluetooth();
  stopScanButton.disabled = !isScanning;
  rememberWatchButton.disabled = isBusy || isScanning || !connection || !selectedDevice?.id;
  clearWatchButton.disabled = isBusy || isScanning || !trustedDevice;
  confirmTargetInput.disabled = isBusy || isScanning || !connection || hasTrustedMismatch();
  sendButton.disabled = isBusy || isScanning || !selectedFile || !connection || !targetConfirmed || hasTrustedMismatch();
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

function hex(value, width) {
  return value.toString(16).padStart(width, "0");
}

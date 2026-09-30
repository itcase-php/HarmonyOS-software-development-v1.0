// Generated catalogue factory; records are instantiated only when queried.
import { RegistryFormat, ConversionRouteDefinition } from '../../models/RegistryTypes';
export function createFormats(): RegistryFormat[] { return [
  {
    "id": "mp3",
    "displayName": "MP3",
    "category": "audio",
    "extensions": [
      "mp3"
    ],
    "mimeTypes": [
      "audio/mpeg"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "wav",
    "displayName": "WAV",
    "category": "audio",
    "extensions": [
      "wav"
    ],
    "mimeTypes": [
      "audio/wav"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "flac",
    "displayName": "FLAC",
    "category": "audio",
    "extensions": [
      "flac"
    ],
    "mimeTypes": [
      "audio/flac"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "aac",
    "displayName": "AAC",
    "category": "audio",
    "extensions": [
      "aac"
    ],
    "mimeTypes": [
      "audio/aac"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "m4a",
    "displayName": "M4A",
    "category": "audio",
    "extensions": [
      "m4a"
    ],
    "mimeTypes": [
      "audio/mp4"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "ogg",
    "displayName": "Ogg",
    "category": "audio",
    "extensions": [
      "ogg"
    ],
    "mimeTypes": [
      "audio/ogg"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "opus",
    "displayName": "Opus",
    "category": "audio",
    "extensions": [
      "opus"
    ],
    "mimeTypes": [
      "audio/opus"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "wma",
    "displayName": "WMA",
    "category": "audio",
    "extensions": [
      "wma"
    ],
    "mimeTypes": [
      "audio/x-ms-wma"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      }
    ],
    "availability": "planned"
  }
]; }
export function createRoutes(): ConversionRouteDefinition[] { return [
  {
    "id": "mp3-wav",
    "from": [
      "mp3"
    ],
    "to": "wav",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "mp3-wav-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "mp3"
        ],
        "outputFormatId": "wav",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  },
  {
    "id": "wav-mp3",
    "from": [
      "wav"
    ],
    "to": "mp3",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "wav-mp3-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "wav"
        ],
        "outputFormatId": "mp3",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  },
  {
    "id": "flac-mp3",
    "from": [
      "flac"
    ],
    "to": "mp3",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "flac-mp3-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "flac"
        ],
        "outputFormatId": "mp3",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  },
  {
    "id": "aac-mp3",
    "from": [
      "aac"
    ],
    "to": "mp3",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "aac-mp3-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "aac"
        ],
        "outputFormatId": "mp3",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  },
  {
    "id": "m4a-mp3",
    "from": [
      "m4a"
    ],
    "to": "mp3",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "m4a-mp3-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "m4a"
        ],
        "outputFormatId": "mp3",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  },
  {
    "id": "ogg-mp3",
    "from": [
      "ogg"
    ],
    "to": "mp3",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "ogg-mp3-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "ogg"
        ],
        "outputFormatId": "mp3",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  },
  {
    "id": "opus-mp3",
    "from": [
      "opus"
    ],
    "to": "mp3",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "media"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "opus-mp3-1",
        "engineIds": [
          "media"
        ],
        "inputFormatIds": [
          "opus"
        ],
        "outputFormatId": "mp3",
        "operation": "convert",
        "executorEngineId": "media"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "audio",
    "validationProfileId": "audio"
  }
]; }

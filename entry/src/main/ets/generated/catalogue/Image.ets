// Generated catalogue factory; records are instantiated only when queried.
import { RegistryFormat, ConversionRouteDefinition } from '../../models/RegistryTypes';
export function createFormats(): RegistryFormat[] { return [
  {
    "id": "jpeg",
    "displayName": "JPEG",
    "category": "image",
    "extensions": [
      "jpg",
      "jpeg"
    ],
    "mimeTypes": [
      "image/jpeg"
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
      },
      {
        "key": "metadataPolicy",
        "kind": "string",
        "stringValue": "preserve_allowed"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "png",
    "displayName": "PNG",
    "category": "image",
    "extensions": [
      "png"
    ],
    "mimeTypes": [
      "image/png"
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
      },
      {
        "key": "metadataPolicy",
        "kind": "string",
        "stringValue": "preserve_allowed"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "webp",
    "displayName": "WebP",
    "category": "image",
    "extensions": [
      "webp"
    ],
    "mimeTypes": [
      "image/webp"
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
      },
      {
        "key": "metadataPolicy",
        "kind": "string",
        "stringValue": "preserve_allowed"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "heif",
    "displayName": "HEIF",
    "category": "image",
    "extensions": [
      "heif",
      "heic"
    ],
    "mimeTypes": [
      "image/heif",
      "image/heic"
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
      },
      {
        "key": "metadataPolicy",
        "kind": "string",
        "stringValue": "preserve_allowed"
      }
    ],
    "availability": "planned"
  }
]; }
export function createRoutes(): ConversionRouteDefinition[] { return [
  {
    "id": "pdf-png",
    "from": [
      "pdf"
    ],
    "to": "png",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "pdf",
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "pdf-png-1",
        "engineIds": [
          "pdf",
          "image"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "png",
        "operation": "convert",
        "executorEngineId": "pdf"
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
    "optionsProfileId": "pdf_render",
    "validationProfileId": "pdf_image"
  },
  {
    "id": "pdf-jpeg",
    "from": [
      "pdf"
    ],
    "to": "jpeg",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "pdf",
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "pdf-jpeg-1",
        "engineIds": [
          "pdf",
          "image"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "jpeg",
        "operation": "convert",
        "executorEngineId": "pdf"
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
    "optionsProfileId": "pdf_render",
    "validationProfileId": "pdf_image"
  },
  {
    "id": "jpeg-png",
    "from": [
      "jpeg"
    ],
    "to": "png",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "jpeg-png-1",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "jpeg"
        ],
        "outputFormatId": "png",
        "operation": "convert",
        "executorEngineId": "image"
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
    "optionsProfileId": "image_convert",
    "validationProfileId": "image"
  },
  {
    "id": "jpeg-webp",
    "from": [
      "jpeg"
    ],
    "to": "webp",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "compatible",
    "engineIds": [
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "jpeg-webp-1",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "jpeg"
        ],
        "outputFormatId": "webp",
        "operation": "convert",
        "executorEngineId": "image"
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
    "optionsProfileId": "image_convert",
    "validationProfileId": "image"
  },
  {
    "id": "png-jpeg",
    "from": [
      "png"
    ],
    "to": "jpeg",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "compatible",
    "engineIds": [
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "png-jpeg-1",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "jpeg",
        "operation": "convert",
        "executorEngineId": "image"
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
    "optionsProfileId": "image_convert",
    "validationProfileId": "image"
  },
  {
    "id": "png-webp",
    "from": [
      "png"
    ],
    "to": "webp",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "compatible",
    "engineIds": [
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "png-webp-1",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "webp",
        "operation": "convert",
        "executorEngineId": "image"
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
    "optionsProfileId": "image_convert",
    "validationProfileId": "image"
  },
  {
    "id": "webp-jpeg",
    "from": [
      "webp"
    ],
    "to": "jpeg",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "compatible",
    "engineIds": [
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "webp-jpeg-1",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "webp"
        ],
        "outputFormatId": "jpeg",
        "operation": "convert",
        "executorEngineId": "image"
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
    "optionsProfileId": "image_convert",
    "validationProfileId": "image"
  },
  {
    "id": "webp-png",
    "from": [
      "webp"
    ],
    "to": "png",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "image"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "webp-png-1",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "webp"
        ],
        "outputFormatId": "png",
        "operation": "convert",
        "executorEngineId": "image"
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
    "optionsProfileId": "image_convert",
    "validationProfileId": "image"
  }
]; }

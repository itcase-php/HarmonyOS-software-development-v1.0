// Generated catalogue factory; records are instantiated only when queried.
import { RegistryFormat, ConversionRouteDefinition } from '../../models/RegistryTypes';
export function createFormats(): RegistryFormat[] { return [
  {
    "id": "pdf",
    "displayName": "PDF",
    "category": "pdf",
    "extensions": [
      "pdf"
    ],
    "mimeTypes": [
      "application/pdf"
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
        "key": "dpi",
        "kind": "number",
        "numberValue": 144
      }
    ],
    "availability": "planned"
  }
]; }
export function createRoutes(): ConversionRouteDefinition[] { return [
  {
    "id": "jpeg-pdf",
    "from": [
      "jpeg"
    ],
    "to": "pdf",
    "operation": "images_to_pdf",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "image",
      "pdf"
    ],
    "priority": 10,
    "status": "experimental",
    "phase": 1,
    "steps": [
      {
        "stepId": "jpeg-pdf-1",
        "engineIds": [
          "image",
          "pdf"
        ],
        "inputFormatIds": [
          "jpeg"
        ],
        "outputFormatId": "pdf",
        "operation": "images_to_pdf",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 100,
      "protectedInputs": "block"
    },
    "optionsProfileId": "images_pdf",
    "validationProfileId": "image_pdf"
  },
  {
    "id": "png-pdf",
    "from": [
      "png"
    ],
    "to": "pdf",
    "operation": "images_to_pdf",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "image",
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 1,
    "steps": [
      {
        "stepId": "png-pdf-1",
        "engineIds": [
          "image",
          "pdf"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "pdf",
        "operation": "images_to_pdf",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [
      "png-pdf-alternate"
    ],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 100,
      "protectedInputs": "block"
    },
    "optionsProfileId": "images_pdf",
    "validationProfileId": "image_pdf"
  },
  {
    "id": "mixed-images-pdf",
    "from": [
      "jpeg",
      "png"
    ],
    "to": "pdf",
    "operation": "images_to_pdf",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "image",
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 1,
    "steps": [
      {
        "stepId": "mixed-images-pdf-1",
        "engineIds": [
          "image",
          "pdf"
        ],
        "inputFormatIds": [
          "jpeg",
          "png"
        ],
        "outputFormatId": "pdf",
        "operation": "images_to_pdf",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 100,
      "protectedInputs": "block"
    },
    "optionsProfileId": "images_pdf",
    "validationProfileId": "image_pdf"
  },
  {
    "id": "pdf_split",
    "from": [
      "pdf"
    ],
    "to": "pdf",
    "operation": "pdf_split",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "pdf_split-1",
        "engineIds": [
          "pdf"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "pdf",
        "operation": "pdf_split",
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
    "optionsProfileId": "pdf_pages",
    "validationProfileId": "pdf_pages"
  },
  {
    "id": "pdf_merge",
    "from": [
      "pdf"
    ],
    "to": "pdf",
    "operation": "pdf_merge",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "pdf_merge-1",
        "engineIds": [
          "pdf"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "pdf",
        "operation": "pdf_merge",
        "executorEngineId": "pdf"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 100,
      "protectedInputs": "block"
    },
    "optionsProfileId": "pdf_pages",
    "validationProfileId": "pdf_pages"
  },
  {
    "id": "webp-pdf",
    "from": [
      "webp"
    ],
    "to": "pdf",
    "operation": "images_to_pdf",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "image",
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "webp-pdf-1",
        "engineIds": [
          "image",
          "pdf"
        ],
        "inputFormatIds": [
          "webp"
        ],
        "outputFormatId": "pdf",
        "operation": "images_to_pdf",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 100,
      "protectedInputs": "block"
    },
    "optionsProfileId": "images_pdf",
    "validationProfileId": "image_pdf"
  },
  {
    "id": "docx-pdf",
    "from": [
      "docx"
    ],
    "to": "pdf",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "office",
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "docx-pdf-1",
        "engineIds": [
          "office",
          "pdf"
        ],
        "inputFormatIds": [
          "docx"
        ],
        "outputFormatId": "pdf",
        "operation": "convert",
        "executorEngineId": "office"
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
    "optionsProfileId": "office_render",
    "validationProfileId": "office_layout"
  },
  {
    "id": "pptx-pdf",
    "from": [
      "pptx"
    ],
    "to": "pdf",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "office",
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pptx-pdf-1",
        "engineIds": [
          "office",
          "pdf"
        ],
        "inputFormatIds": [
          "pptx"
        ],
        "outputFormatId": "pdf",
        "operation": "convert",
        "executorEngineId": "office"
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
    "optionsProfileId": "office_render",
    "validationProfileId": "office_layout"
  },
  {
    "id": "png-pdf-alternate",
    "from": [
      "png"
    ],
    "to": "pdf",
    "operation": "images_to_pdf",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "extreme",
    "engineIds": [
      "image",
      "pdf"
    ],
    "priority": 20,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "png-pdf-alternate-1",
        "engineIds": [
          "image",
          "pdf"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "pdf",
        "operation": "images_to_pdf",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [
      "png-pdf-compatible"
    ],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 100,
      "protectedInputs": "block"
    },
    "optionsProfileId": "images_pdf",
    "validationProfileId": "image_pdf"
  },
  {
    "id": "png-pdf-compatible",
    "from": [
      "png"
    ],
    "to": "pdf",
    "operation": "images_to_pdf",
    "pathMode": "relay",
    "intent": "layout_preserved",
    "fidelityTier": "compatible",
    "engineIds": [
      "image",
      "pdf"
    ],
    "priority": 30,
    "status": "planned",
    "phase": 2,
    "steps": [
      {
        "stepId": "normalize",
        "engineIds": [
          "image"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "jpeg",
        "operation": "convert",
        "executorEngineId": "image"
      },
      {
        "stepId": "write-pdf",
        "engineIds": [
          "image",
          "pdf"
        ],
        "inputFormatIds": [
          "jpeg"
        ],
        "outputFormatId": "pdf",
        "operation": "images_to_pdf",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": true,
    "allowedDegradations": [
      "alpha_flatten",
      "jpeg_reencode"
    ],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "images_pdf",
    "validationProfileId": "image_pdf"
  }
]; }

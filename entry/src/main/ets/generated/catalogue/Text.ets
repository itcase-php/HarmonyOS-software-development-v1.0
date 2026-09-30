// Generated catalogue factory; records are instantiated only when queried.
import { RegistryFormat, ConversionRouteDefinition } from '../../models/RegistryTypes';
export function createFormats(): RegistryFormat[] { return [
  {
    "id": "txt",
    "displayName": "纯文本",
    "category": "text",
    "extensions": [
      "txt"
    ],
    "mimeTypes": [
      "text/plain"
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
    "id": "md",
    "displayName": "Markdown",
    "category": "text",
    "extensions": [
      "md",
      "markdown"
    ],
    "mimeTypes": [
      "text/markdown"
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
    "id": "pdf-txt",
    "from": [
      "pdf"
    ],
    "to": "txt",
    "operation": "extract_text",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pdf-txt-1",
        "engineIds": [
          "pdf"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "txt",
        "operation": "extract_text",
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
    "optionsProfileId": "pdf_content",
    "validationProfileId": "content"
  },
  {
    "id": "pdf-md",
    "from": [
      "pdf"
    ],
    "to": "md",
    "operation": "extract_text",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pdf-md-1",
        "engineIds": [
          "pdf"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "md",
        "operation": "extract_text",
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
    "optionsProfileId": "pdf_content",
    "validationProfileId": "content"
  },
  {
    "id": "docx-txt",
    "from": [
      "docx"
    ],
    "to": "txt",
    "operation": "extract_text",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "docx-txt-1",
        "engineIds": [
          "office"
        ],
        "inputFormatIds": [
          "docx"
        ],
        "outputFormatId": "txt",
        "operation": "extract_text",
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
    "optionsProfileId": "office_content",
    "validationProfileId": "content"
  },
  {
    "id": "docx-md",
    "from": [
      "docx"
    ],
    "to": "md",
    "operation": "extract_text",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "docx-md-1",
        "engineIds": [
          "office"
        ],
        "inputFormatIds": [
          "docx"
        ],
        "outputFormatId": "md",
        "operation": "extract_text",
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
    "optionsProfileId": "office_content",
    "validationProfileId": "content"
  },
  {
    "id": "pptx-txt",
    "from": [
      "pptx"
    ],
    "to": "txt",
    "operation": "extract_text",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pptx-txt-1",
        "engineIds": [
          "office"
        ],
        "inputFormatIds": [
          "pptx"
        ],
        "outputFormatId": "txt",
        "operation": "extract_text",
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
    "optionsProfileId": "office_content",
    "validationProfileId": "content"
  },
  {
    "id": "pptx-md",
    "from": [
      "pptx"
    ],
    "to": "md",
    "operation": "extract_text",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pptx-md-1",
        "engineIds": [
          "office"
        ],
        "inputFormatIds": [
          "pptx"
        ],
        "outputFormatId": "md",
        "operation": "extract_text",
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
    "optionsProfileId": "office_content",
    "validationProfileId": "content"
  },
  {
    "id": "png-txt-ocr",
    "from": [
      "png"
    ],
    "to": "txt",
    "operation": "ocr_extract",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "image",
      "ocr"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "png-txt-ocr-1",
        "engineIds": [
          "image",
          "ocr"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "txt",
        "operation": "ocr_extract",
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
    "optionsProfileId": "ocr",
    "validationProfileId": "ocr"
  },
  {
    "id": "jpeg-txt-ocr",
    "from": [
      "jpeg"
    ],
    "to": "txt",
    "operation": "ocr_extract",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "image",
      "ocr"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "jpeg-txt-ocr-1",
        "engineIds": [
          "image",
          "ocr"
        ],
        "inputFormatIds": [
          "jpeg"
        ],
        "outputFormatId": "txt",
        "operation": "ocr_extract",
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
    "optionsProfileId": "ocr",
    "validationProfileId": "ocr"
  },
  {
    "id": "pdf-txt-ocr",
    "from": [
      "pdf"
    ],
    "to": "txt",
    "operation": "ocr_extract",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf",
      "image",
      "ocr"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "pdf-txt-ocr-1",
        "engineIds": [
          "pdf",
          "image",
          "ocr"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "txt",
        "operation": "ocr_extract",
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
    "optionsProfileId": "ocr",
    "validationProfileId": "ocr"
  }
]; }

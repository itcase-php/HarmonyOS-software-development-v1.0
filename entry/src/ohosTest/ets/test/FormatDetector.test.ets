import { describe, it, expect } from '@ohos/hypium';
import { FormatDetector } from '../../../main/ets/services/FormatDetector';
import { FormatRegistry } from '../../../main/ets/services/FormatRegistry';

export default function formatDetectorTest() {
  describe('FormatDetector', () => {
    it('covers every extension in the complete approved catalogue', 0, () => {
      const formats = FormatRegistry.listFormats();
      expect(formats.length).assertEqual(18);
      for (const format of formats) {
        for (const extension of format.extensions) {
          expect(FormatDetector.detectByExtension(`source.${extension.toUpperCase()}`)).assertEqual(format.id);
        }
      }
    });
    it('covers registered MIME values including case and parameters', 0, () => {
      for (const format of FormatRegistry.listFormats()) {
        for (const mime of format.mimeTypes) {
          expect(FormatDetector.detectByMime(`${mime.toUpperCase()}; charset=utf-8`)).assertEqual(format.id);
        }
      }
    });
    it('normalizes jpg through the registered jpeg extension', 0, () => {
      expect(FormatDetector.detect('photo.JPG', '')).assertEqual('jpeg');
    });
    it('prefers the extension when MIME disagrees', 0, () => {
      expect(FormatDetector.detect('source.pdf', 'image/png')).assertEqual('pdf');
    });
    it('uses MIME when no registered extension exists', 0, () => {
      expect(FormatDetector.detect('source.unknown', 'application/pdf')).assertEqual('pdf');
    });
    it('does not invent unsupported formats or treat a trailing dot as an extension', 0, () => {
      expect(FormatDetector.detect('source.doc', 'application/unknown')).assertEqual('');
      expect(FormatDetector.detectByExtension('source.')).assertEqual(null);
    });
  });
}

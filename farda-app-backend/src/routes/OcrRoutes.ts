import { detectImageMime, extractPrescriptionFromBuffers, OcrExtractionError } from '@src/services/OcrService';
import type { Request, Response, NextFunction } from 'express';
import multer from 'multer';
import { authenticatedUser, createPrescription, listDoses, listPrescriptions, recordDose, sendConsumerError } from './PrescriptionRoutes';

class InvalidImageUpload extends Error {}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024, files: 4, fields: 4, parts: 8 },
  // Reject the whole batch instead of silently dropping an unsupported view.
  fileFilter: (_req, file, cb) => ['image/jpeg', 'image/png', 'image/webp'].includes(file.mimetype)
    ? cb(null, true) : cb(new InvalidImageUpload()),
}).array('image', 4);

const boundedUpload = (req: Request, res: Response, next: NextFunction) => {
  upload(req, res, error => {
    if (error instanceof InvalidImageUpload) return res.status(400).json({ error: 'Choose valid JPEG, PNG or WebP label images', code: 'invalid_image' });
    if (error) return res.status(413).json({ error: 'Upload up to four images, at most 8 MB each', code: 'upload_limit' });
    return next();
  });
};

const OcrRoutes = {
  extractFromImages: [boundedUpload, async (req: Request, res: Response) => {
    try {
      authenticatedUser(req);
      const files = Array.isArray(req.files) ? req.files : [];
      if (!files.length || files.some(file => detectImageMime(file.buffer) !== file.mimetype)) return res.status(400).json({ error: 'Choose valid JPEG, PNG or WebP label images', code: 'invalid_image' });
      return res.json(await extractPrescriptionFromBuffers(files.map(file => file.buffer)));
    } catch (error) {
      if (error instanceof OcrExtractionError) {
        const status = error.code === 'ocr_incomplete' ? 422 : error.code === 'ocr_timeout' ? 504 : 503;
        return res.status(status).json({ error: error.message, code: error.code });
      }
      return sendConsumerError(res, error);
    }
  }],
  extractFromUrls: (_req: Request, res: Response) => res.status(422).json({ error: 'Upload label images directly. Remote image URLs are not supported.', code: 'unsupported_input' }),
  // Legacy aliases retain authentication but require the same explicit reviewed
  // canonical schema. There is no caller-supplied userId or one-user upsert.
  savePrescription: createPrescription,
  getUserPrescriptions: listPrescriptions,
  getUserDoses: listDoses,
  recordDoseMood: recordDose,
};
export default OcrRoutes;

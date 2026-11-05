-- Kura #27 - Gercek YOLOv8n-seg / YOLO11n-seg deneyi
-- PostgreSQL 16+ / pgAdmin 4 uyumludur.
-- GEREKLI: Colab sonuc ZIP icinden asagidaki dokuz CSV dosyasini cikartin.
-- Bu dosya veri UYDURMAZ; CSV'ler yalnızca iki model gerçekten çalıştırıldıktan sonra oluşur.
-- pgAdmin ile IMPORT yapin (Header=Yes; Encoding=UTF8; Delimiter=,).

BEGIN;

CREATE TABLE IF NOT EXISTS models (
 model_name TEXT PRIMARY KEY,
 CONSTRAINT model_adi CHECK (model_name = lower(btrim(model_name)) AND model_name <> '')
);
CREATE TABLE IF NOT EXISTS images (
 id BIGINT PRIMARY KEY,
 package_type TEXT NOT NULL,
 captured_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS true_labels (
 id BIGINT PRIMARY KEY,
 goruntu_id BIGINT NOT NULL REFERENCES images(id),
 label TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS model_detections (
 id BIGINT PRIMARY KEY,
 goruntu_id BIGINT NOT NULL REFERENCES images(id),
 model_name TEXT NOT NULL REFERENCES models(model_name),
 label TEXT NOT NULL,
 confidence NUMERIC(8,6) CHECK (confidence BETWEEN 0 AND 1),
 latency_ms NUMERIC(12,3) CHECK (latency_ms >= 0)
);

-- Ek tablolar: nesne tespiti icin bbox/IoU; sifir tespitli kareler icin cikarim gunlugu.
CREATE TABLE IF NOT EXISTS true_label_boxes (
 true_label_id BIGINT PRIMARY KEY REFERENCES true_labels(id),
 x1 NUMERIC(9,6), y1 NUMERIC(9,6), x2 NUMERIC(9,6), y2 NUMERIC(9,6)
);
CREATE TABLE IF NOT EXISTS detection_boxes (
 detection_id BIGINT PRIMARY KEY REFERENCES model_detections(id),
 x1 NUMERIC(9,6), y1 NUMERIC(9,6), x2 NUMERIC(9,6), y2 NUMERIC(9,6)
);
CREATE TABLE IF NOT EXISTS model_inference_runs (
 model_name TEXT NOT NULL REFERENCES models(model_name),
 goruntu_id BIGINT NOT NULL REFERENCES images(id),
 latency_ms NUMERIC(12,3) NOT NULL CHECK (latency_ms >= 0),
 tespit_sayisi INTEGER NOT NULL CHECK (tespit_sayisi >= 0),
 cihaz TEXT NOT NULL,
 PRIMARY KEY (model_name, goruntu_id)
);
CREATE TABLE IF NOT EXISTS detection_matches (
 model_name TEXT NOT NULL REFERENCES models(model_name),
 goruntu_id BIGINT NOT NULL REFERENCES images(id),
 package_type TEXT NOT NULL,
 detection_id BIGINT REFERENCES model_detections(id),
 true_label_id BIGINT REFERENCES true_labels(id),
 durum TEXT NOT NULL CHECK (durum IN ('TP','FP','FN')),
 iou NUMERIC(7,5),
 CONSTRAINT ck_match_integrity CHECK (
   (durum='TP' AND detection_id IS NOT NULL AND true_label_id IS NOT NULL AND iou >= 0.5)
OR (durum='FP' AND detection_id IS NOT NULL AND true_label_id IS NULL)
OR (durum='FN' AND detection_id IS NULL AND true_label_id IS NOT NULL)
 )
);
CREATE INDEX IF NOT EXISTS ix_match_model_tur ON detection_matches(model_name,package_type);
CREATE INDEX IF NOT EXISTS ix_infer_model_goruntu ON model_inference_runs(model_name,goruntu_id);

INSERT INTO models(model_name) VALUES ('yolov8n_seg'),('yolo11n_seg')
ON CONFLICT DO NOTHING;
COMMIT;


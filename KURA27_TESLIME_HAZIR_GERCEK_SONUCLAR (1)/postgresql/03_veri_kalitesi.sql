-- Kura 27: PostgreSQL veri temizligi ve kalite kontrolleri.
-- Gercek deney gecikmeleri zaten ms cinsinden yazilir; bu sorgular
-- birim, BOS / NULL ve tutarlilik sorunlarini analiz eder.

-- Test: ham veri boyutlari ve model basina sayilar.
SELECT model_name, COUNT(*) AS tespit, COUNT(DISTINCT goruntu_id) AS tespit_olan_goruntu,
       MIN(latency_ms) AS min_ms, ROUND(AVG(latency_ms),2) AS satir_bazli_ortalama_ms,
       MAX(latency_ms) AS max_ms
FROM model_detections GROUP BY model_name ORDER BY model_name;

-- Dogru gecikme ortalamasi: KARE bazli kayitlardan (tespit satiri agirliklandirmasi yok).
SELECT model_name, COUNT(*) AS islenen_goruntu,
       ROUND(AVG(latency_ms),2) AS gercek_ortalama_ms,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY latency_ms)::NUMERIC,2) AS p50_ms
FROM model_inference_runs GROUP BY model_name ORDER BY model_name;

-- Eksik ve bozuk veri denetimi.
SELECT
  (SELECT COUNT(*) FROM images WHERE package_type IS NULL OR btrim(package_type)='') AS bos_paket_turu,
  (SELECT COUNT(*) FROM model_detections WHERE label IS NULL OR btrim(label)='') AS bos_model_etiketi,
  (SELECT COUNT(*) FROM model_detections WHERE confidence IS NULL) AS eksik_guven,
  (SELECT COUNT(*) FROM model_detections WHERE latency_ms IS NULL) AS eksik_gecikme,
  (SELECT COUNT(*) FROM model_detections WHERE label <> lower(btrim(label))) AS normalize_edilmemis_etiket,
  (SELECT COUNT(*) FROM model_inference_runs WHERE latency_ms < 0) AS negatif_gecikme;

-- Her model-goruntu cifti icin gercek detections ile gunluk kaydinin tutarliligi.
WITH t AS (
 SELECT r.model_name,r.goruntu_id,r.tespit_sayisi,COUNT(d.id) AS sayilan
 FROM model_inference_runs r LEFT JOIN model_detections d
  ON r.model_name=d.model_name AND r.goruntu_id=d.goruntu_id
 GROUP BY r.model_name,r.goruntu_id,r.tespit_sayisi
)
SELECT COUNT(*) FILTER (WHERE tespit_sayisi<>sayilan) AS tutarsiz_cift,
 COUNT(*) AS toplam_cift FROM t;

-- Eger dis CSV dosyalarinda gecikme sayilari '0.23s', '230ms' seklinde gelirse
-- metin -> ms donusumu asagidaki normalizasyon fonksiyonuyla yapilir.
CREATE OR REPLACE FUNCTION normalize_latency_ms(raw_value TEXT)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v TEXT:=lower(btrim(raw_value)); n NUMERIC;
BEGIN
  IF v IS NULL OR v='' THEN RETURN NULL; END IF;
  IF v !~ '^([0-9]+([.,][0-9]+)?)([[:space:]]*(ms|s))?$' THEN
    RAISE EXCEPTION 'Gecersiz latency ifadesi: %',raw_value;
  END IF;
  n:=REPLACE(SUBSTRING(v FROM '^([0-9]+([.,][0-9]+)?)'), ',', '.')::NUMERIC;
  IF v ~ '[[:space:]]*s$' AND v !~ 'ms$' THEN RETURN n * 1000; END IF;
  RETURN n;
END $$;

-- CASE WHEN'i destekleyen örnek birim testleri:
SELECT normalize_latency_ms('0.23s') AS saniyeden_ms,
       normalize_latency_ms('230ms') AS milisaniye,
       normalize_latency_ms('230') AS birimsiz_ms;

-- Tanimli birimsiz degerler otomatik olarak 'ms' varsayilir. Birim bilgisi
-- olmadan gercek 0.23 degeri saniye mi ms mi anlasilamaz; manuel kontrol gerekir.

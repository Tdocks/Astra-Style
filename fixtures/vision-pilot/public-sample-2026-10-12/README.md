# Public-photo scanner pilot

Source: [Alexey Grigorev's Clothing Dataset](https://github.com/alexeygrigorev/clothing-dataset).
The publisher releases it under CC0-1.0; the accompanying LICENSE is retained.
These are real contributed garment photos, not generated images. No contributor
identifiers were copied. The selected images show garments without visible people.

Selection was frozen before any provider request: first two non-kids entries for
T-Shirt, Polo, Shirt, Pants, Shorts, Outwear, Blazer and Shoes in the publisher's
images.csv. Source image URLs, source classes, hashes, independent visual color/
pattern annotations and subjective formality anchors are in manifest.json.
Image 13's source Blazer label was corrected to a coat before requests based on
its visibly long belted silhouette. Some sources depict women's garments; this
tests closet classification of supported categories rather than gender inference.

Photos cover flat lays, hangers, patterned backgrounds, low contrast, stripes,
checks, prints, color blocking and both casual and dressier garments. Images are
400–800 pixels wide and represent an initial convenience sample, not a random
population sample or a validation of camera capture/lighting on the owner's phone.

The deployed scanner receives only the owned uploaded photograph. It receives
no source class, expected attributes, filename labels, device category hint or OCR
prior. Three runs use distinct idempotency keys so retries/caching cannot simulate
repeatability. The hosted harness creates its own confirmed fixture account,
uploads through the authenticated private storage boundary, then removes and
checks both the uploaded images and fixture account.

Run `scripts/run_hosted_vision_pilot.py` with this manifest, an owner-only temporary
Supabase API-key JSON file, an output path and `--repetitions 3`. It never logs the
keys or session. Exit 0 means all recorded pilot thresholds pass; 1 means a
complete run missed a threshold; 2 means infrastructure/cleanup was incomplete.
Thresholds follow scripts/vision_pilot_gate.ts: category 98%, subtype 80%, color
90%, pattern 85%, formality within ±15 for 85%, p50 ≤5.5 seconds, and ≤15% of
photos with a changed pass/fail verdict per field across repetitions. Raw wording
disagreement is separately reported and is not a semantic accuracy failure.

Passing this small public sample does not close the master-plan user-photo pilot
gate. Color and formality annotations contain judgment, this does not test material
or brand truth, and repeated measurements are not independent new garments.

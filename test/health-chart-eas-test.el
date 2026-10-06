;;; health-chart-eas-test.el --- Charts drawn by eas templates -*- lexical-binding: t; -*-

;; The eas backend: adapters, the domain transforms (status,
;; reference-band, change, staleness, trend), every kind's template
;; checked and drawn as text and SVG, its numbers checked against the
;; kind's own chartspec/v1 (`health-chart-eas-parity'), backend selection
;; and the Vega-Lite export.  Everything skips without eas.el: run with
;; `make test EAS=/path/to/eas.el'.

;;; Code:

(require 'health-chart-test-helpers)
(require 'health-chart-backend-test)

(defconst health-chart-eas-test--available
  (and (locate-library "eas") (progn (require 'health-chart-eas-route nil t) t))
  "Non-nil when eas.el is on `load-path' and the route loaded.")

(defmacro health-chart-eas-test--when-eas (&rest body)
  "Run BODY in the test environment with the eas backend first, or skip."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless health-chart-eas-test--available)
     (health-chart-test-env
       (let ((health-chart-graphic-backends '(eas vega-lite gnuplot))
             (health-chart-terminal-backends '(eas gnuplot text)))
         ,@body))))

(defun health-chart-eas-test--kinds ()
  "The kinds with an eas template, in table order."
  (mapcar #'car health-chart-eas-kinds))

(defun health-chart-eas-test--props (kind)
  "The golden props of KIND (the sample panel's)."
  (cdr (assq kind health-chart-backend-test--specs)))

(defun health-chart-eas-test--text (kind &rest props)
  "KIND over the sample panel drawn by eas as plain text under PROPS."
  (substring-no-properties
   (apply #'health-chart-render kind (health-chart-backend-test--data kind)
          :backend 'eas :format 'text
          (append props (health-chart-eas-test--props kind)))))

(defun health-chart-eas-test--transform (name rows &rest params)
  "ROWS (a list) through eas domain transform NAME with PARAMS, as a list."
  (append (eas-transform-apply-domain (append (list :x-eas:transform name) params)
                                      (vconcat rows))
          nil))

;; -----------------------------------------------------------------------
;; Registry
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-every-templated-kind-has-a-template ()
  (health-chart-eas-test--when-eas
    (should (equal (sort (mapcar #'symbol-name (health-chart-eas-test--kinds)) #'string<)
                   (sort (mapcar (lambda (s) (symbol-name (car s)))
                                 health-chart-backend-test--specs)
                         #'string<)))
    (dolist (kind (health-chart-eas-test--kinds))
      (let ((file (health-chart-eas-template-file kind)))
        (should (file-readable-p file))
        (should (string-suffix-p (format "templates/eas/health-%s.json" kind) file))
        (should (member (health-chart-eas-template kind) (eas-template-names)))))
    ;; a flat eas namespace: ours never shadow eas's own templates
    (dolist (name (eas-template-names))
      (when (string-prefix-p "health-" name)
        (should (rassoc name (mapcar (lambda (e) (cons (car e) (plist-get (cdr e) :template)))
                                     health-chart-eas-kinds)))))))

(ert-deftest health-chart-eas-test-listed-with-the-other-templates ()
  (health-chart-eas-test--when-eas
    (let ((listed (seq-filter (lambda (tpl) (eq (plist-get tpl :backend) 'eas))
                              (health-chart-templates))))
      (should (= (length listed) (length health-chart-eas-kinds)))
      (should (seq-every-p (lambda (tpl) (eq (plist-get tpl :source) 'bundled)) listed)))
    (should (memq 'eas (plist-get (health-chart-describe-kind 'bullet) :templates)))
    (should-not (memq 'eas (plist-get (health-chart-describe-kind 'table) :templates)))))

(ert-deftest health-chart-eas-test-adapters-and-transforms-are-registered ()
  (health-chart-eas-test--when-eas
    (dolist (name '("biomarker" "indicator-values"))
      (should (assoc name eas-adapters)))
    (dolist (name '("status" "reference-band" "change" "staleness" "trend"))
      (let ((tr (assoc name eas-transforms)))
        (should tr)
        (should (stringp (plist-get (cdr tr) :doc)))))))

(ert-deftest health-chart-eas-test-templates-check-native ()
  "Each template's example passes eas's own check and needs no static fallback."
  (health-chart-eas-test--when-eas
    (require 'eas-agent)
    (dolist (kind (health-chart-eas-test--kinds))
      (let* ((name (health-chart-eas-template kind))
             (result (eas-agent "check" name :data (eas-template-example name))))
        (should (eq (plist-get result :ok) t))
        (should (eq (plist-get (plist-get result :data) :native) t))))))

(ert-deftest health-chart-eas-test-real-bindings-check-native ()
  "The bindings a kind builds from the sample panel resolve to a native spec."
  (health-chart-eas-test--when-eas
    (dolist (kind (health-chart-eas-test--kinds))
      (let ((resolved (health-chart-eas-resolve kind (health-chart-backend-test--data kind)
                                                (health-chart-eas-test--props kind))))
        (should resolved)
        (should-not (eas-spec-unsupported resolved))
        ;; pure Vega-Lite: no x-eas keys survive
        (should-not (string-match-p "x-eas" (eas-json-encode resolved)))))))

;; -----------------------------------------------------------------------
;; Adapters
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-biomarker-adapter-reads-every-form ()
  (health-chart-eas-test--when-eas
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"
                                    :marker "ldl-c"))
           (rows (eas-data-rows (eas-data-from "biomarker" ms))))
      (should (= (length rows) (length ms)))
      (should (equal (plist-get (aref rows 0) :label) "LDL-C"))
      (should (equal (plist-get (aref rows 0) :ref_high) 100))
      (should (eq (plist-get (aref rows 0) :ref_low) 0))
      ;; JSON arrays, snake_case members and a biomarker/v1 envelope
      (let* ((json (json-encode (list (cons 'schema "biomarker/v1")
                                      (cons 'measurements
                                            (vconcat (mapcar #'health-chart-source-to-json ms))))))
             (again (eas-data-rows (eas-data-from "biomarker" (json-parse-string
                                                                json :object-type 'plist)))))
        (should (equal (mapcar (lambda (r) (plist-get r :value)) (append again nil))
                       (mapcar (lambda (r) (plist-get r :value)) (append rows nil)))))
      (should (equal (eas-data-rows (eas-data-from "biomarker" (vconcat ms))) rows)))))

(ert-deftest health-chart-eas-test-biomarker-adapter-fills-missing-ranges ()
  (health-chart-eas-test--when-eas
    (let* ((a (health-chart-test-m :date "2025-01-01" :ref-high 100 :ref-low 0))
           (b (health-chart-test-m :date "2025-02-01"))
           (rows (eas-data-rows (eas-data-from "biomarker" (list a b)))))
      (should (equal (plist-get (aref rows 1) :ref_high) 100)))))

(ert-deftest health-chart-eas-test-adapters-fail-as-data ()
  (health-chart-eas-test--when-eas
    (let ((err (should-error (eas-data-from "biomarker"
                                            (list (health-chart-test-m)
                                                  (list :marker "ldl_c" :date "2025-02-31x"
                                                        :value 1)))
                             :type 'eas-error)))
      (should (equal (plist-get (cddr err) :code) "SHAPE_INVALID"))
      (should (eql (plist-get (cddr err) :index) 1)))
    (let ((err (should-error (eas-data-from "indicator-values" (list (list :value 3)))
                             :type 'eas-error)))
      (should (equal (plist-get (cddr err) :code) "SHAPE_INVALID"))
      (should (eql (plist-get (cddr err) :index) 0)))))

;; -----------------------------------------------------------------------
;; Transforms
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-status-agrees-with-health-chart-status ()
  (health-chart-eas-test--when-eas
    (let* ((ms (health-chart-fill-ranges (health-chart-backend-test-sample)))
           (rows (health-chart-eas-test--transform
                  "status" (append (eas-data-rows (eas-data-from "biomarker" ms)) nil))))
      (should (= (length rows) (length ms)))
      (cl-loop for row in rows for m in ms
               for status = (health-chart-status m)
               do (should (equal (plist-get row :status) (symbol-name status)))
               (should (equal (plist-get row :status_label) (health-chart-status-label status)))
               (should (equal (plist-get row :glyph) (health-chart-status-glyph status)))
               (should (equal (plist-get row :value_label) (health-chart-fmt-value m)))
               (should (= (plist-get row :out) (if (health-chart-out-of-range-p m) 1 0)))))))

(ert-deftest health-chart-eas-test-reference-band-value-scale ()
  (health-chart-eas-test--when-eas
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"
                                    :marker "ldl-c"))
           (rows (append (eas-data-rows (eas-data-from "biomarker" ms)) nil))
           (out (health-chart-eas-test--transform "reference-band" rows :scale "value"))
           (row (car out))
           (model (health-chart-model-series ms)))
      ;; the band extents are the model's, clamped to its padded range
      (should (equal (plist-get row :ref_label) "reference 0–100"))
      (should (equal (plist-get row :opt_label) "optimal ≤70"))
      (should (equal (plist-get row :band_note) "reference 0–100 · optimal ≤70"))
      (let ((range (health-chart-spec--floor-zero (plist-get model :y-range)
                                                  (mapcar #'cadr (plist-get (car (plist-get model :lines)) :points)))))
        (should (equal (plist-get row :y_lo) (health-chart-spec--round (car range))))
        (should (equal (plist-get row :y_hi) (health-chart-spec--round (cdr range)))))
      (should (= (plist-get row :ref_y) (plist-get row :y_lo)))
      (should (= (plist-get row :ref_y2) 100))
      (should (= (plist-get row :opt_y2) 70))
      (should (stringp (plist-get row :x_lo)))
      (should (string< (plist-get row :x_lo) "2021-11-08"))
      ;; bands off
      (let ((off (car (health-chart-eas-test--transform "reference-band" rows :ref :false
                                                        :optimal :false))))
        (should (eq (plist-get off :ref_y) :null))
        (should (equal (plist-get off :band_note) ""))))))

(ert-deftest health-chart-eas-test-reference-band-domain-and-range-scales ()
  (health-chart-eas-test--when-eas
    (let* ((latest (health-chart-latest (health-chart-filter (health-chart-backend-test-sample)
                                                             :person "alex")))
           (rows (append (eas-data-rows (eas-data-from "biomarker" latest)) nil))
           (bullet (health-chart-eas-test--transform "reference-band" rows :scale "domain"))
           (model (health-chart-model-bullet (health-chart-backend-test-sample) :person "alex")))
      (cl-loop for row in bullet for r in model
               do (should (health-chart-eas--same-p
                           (plist-get row :pos)
                           (health-chart-spec--position (plist-get r :value) (plist-get r :domain))))))
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"))
           (rows (append (eas-data-rows (eas-data-from "biomarker" ms)) nil))
           (out (health-chart-eas-test--transform "reference-band" rows :scale "range"))
           (ldl (seq-find (lambda (r) (equal (plist-get r :marker) "ldl-c")) out)))
      (should (< (plist-get ldl :norm) 3))
      (should (= (plist-get ldl :ref_x) 0))
      (should (= (plist-get ldl :ref_x2) 1))
      (should (<= (plist-get ldl :x_lo) (plist-get ldl :x)))
      (should (>= (plist-get ldl :x_hi) (plist-get ldl :x))))
    ;; 0 at the reference low, 1 at the reference high
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"
                                    :marker "ldl-c"))
           (rows (append (eas-data-rows (eas-data-from "biomarker" ms)) nil))
           (pair (list (plist-put (copy-sequence (nth 0 rows)) :value 0)
                       (plist-put (copy-sequence (nth 1 rows)) :value 100)))
           (out (health-chart-eas-test--transform "reference-band" pair :scale "range")))
      (should (= (plist-get (nth 0 out) :norm) 0))
      (should (= (plist-get (nth 1 out) :norm) 1)))))

(ert-deftest health-chart-eas-test-reference-band-drops-markers-without-ranges ()
  (health-chart-eas-test--when-eas
    (let* ((bare (list :person "p" :marker "m" :value 3 :unit "u" :date "2025-01-01"))
           (rows (append (eas-data-rows (eas-data-from "biomarker" (list bare))) nil)))
      (should-not (health-chart-eas-test--transform "reference-band" rows :scale "range")))))

(ert-deftest health-chart-eas-test-change-pairs-first-and-last-draw ()
  (health-chart-eas-test--when-eas
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"
                                    :marker '("ldl-c" "hscrp")))
           (rows (append (eas-data-rows (eas-data-from "biomarker" ms)) nil))
           (out (health-chart-eas-test--transform "change" rows))
           (ldl (seq-find (lambda (r) (equal (plist-get r :marker) "ldl-c")) out)))
      (should (= (length out) 2))
      (should (equal (plist-get ldl :date_before) "2021-11-08"))
      (should (equal (plist-get ldl :date_after) "2025-09-15"))
      (should (= (plist-get ldl :before) 162))
      (should (= (plist-get ldl :after) 76))
      (should (equal (plist-get ldl :verdict) "improved"))
      (should (equal (plist-get ldl :verdict_label) "✔ improved"))
      (should (equal (plist-get ldl :pct_label) "-53.1%"))
      (should (equal (plist-get ldl :side) "neg"))
      (should (> (plist-get ldl :lim) 53))
      ;; a marker with one draw has no change
      (should-not (health-chart-eas-test--transform "change" (list (car rows)))))))

(ert-deftest health-chart-eas-test-staleness-days-and-states ()
  (health-chart-eas-test--when-eas
    (let* ((values (health-chart-backend-test-indicators))
           (rows (append (eas-data-rows (eas-data-from "indicator-values" values)) nil))
           (out (health-chart-eas-test--transform "staleness" rows :as_of "2026-03-01"
                                                  :due_days 120 :stale_days 365))
           (model (health-chart-model-staleness values :as-of "2026-03-01")))
      (should (equal (mapcar (lambda (r) (plist-get r :id)) out)
                     (mapcar (lambda (r) (plist-get r :id)) (plist-get model :rows))))
      (cl-loop for row in out for r in (plist-get model :rows)
               do (should (equal (plist-get row :days) (or (plist-get r :days) :null)))
               (should (equal (plist-get row :state) (symbol-name (plist-get r :state)))))
      ;; the default as-of is the data's own
      (should (equal (plist-get (car (health-chart-eas-test--transform "staleness" rows))
                                :as_of_date)
                     "2025-10-01")))))

(ert-deftest health-chart-eas-test-trend-fit-and-roll ()
  (health-chart-eas-test--when-eas
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"
                                    :marker "ldl-c"))
           (rows (append (eas-data-rows (eas-data-from "biomarker" ms)) nil))
           (out (health-chart-eas-test--transform "trend" rows))
           (spec (health-chart-spec 'trend (health-chart-backend-test-sample)
                                    :person "alex" :marker "ldl-c")))
      (cl-loop for row in out for s in (append (plist-get spec :rows) nil)
               do (should (health-chart-eas--same-p (plist-get row :roll) (plist-get s :roll)))
               (should (health-chart-eas--same-p (plist-get row :fit) (plist-get s :fit))))
      (should (equal (plist-get (car out) :trend_label)
                     (plist-get (plist-get (plist-get spec :layout) :trend) :label)))
      ;; fewer than three draws: no fit
      (should (equal (plist-get (car (health-chart-eas-test--transform "trend" (seq-take rows 2)))
                                :trend_label)
                     "trend needs three draws")))))

;; -----------------------------------------------------------------------
;; Rendering
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-every-kind-draws-as-text ()
  (health-chart-eas-test--when-eas
    (dolist (kind (health-chart-eas-test--kinds))
      (let ((text (health-chart-eas-test--text kind)))
        (should (> (length (split-string text "\n")) 8))
        ;; the title says what is drawn
        (should (string-match-p (pcase kind
                                  ('timeseries "LDL-C · alex")
                                  ('panel "Panel · alex")
                                  ('bullet "Latest vs range · alex")
                                  ('heatmap "Status by draw · alex")
                                  ('compare "Vitamin D · alex vs sam")
                                  ('delta "Change .* → .* · alex")
                                  ('staleness "Days since draw · sample")
                                  ('trend "LDL-C · alex")
                                  ('lollipop "hs-CRP · alex")
                                  ('strip "Every draw vs range · alex")
                                  ('dumbbell "First vs latest draw · alex")
                                  ('dual "Glucose · HbA1c · alex")
                                  ('inrange "Draws by status · alex"))
                                text))
        ;; status is never color alone: a glyph and word beside every color
        (should (string-match-p "●\\|◐\\|▲\\|▼\\|○\\|✔\\|✖\\|→" text))))))

(ert-deftest health-chart-eas-test-text-has-status-words ()
  (health-chart-eas-test--when-eas
    (dolist (kind '(timeseries panel bullet heatmap compare trend lollipop strip dual inrange))
      (should (string-match-p "optimal\\|suboptimal\\|normal\\|high\\|low"
                              (health-chart-eas-test--text kind))))
    (dolist (kind '(delta dumbbell))
      (should (string-match-p "improved\\|worsened\\|steady\\|on-target"
                              (health-chart-eas-test--text kind))))
    (should (string-match-p "fresh\\|due\\|stale" (health-chart-eas-test--text 'staleness)))))

(ert-deftest health-chart-eas-test-text-follows-width-and-keeps-help-echo ()
  (health-chart-eas-test--when-eas
    (let* ((narrow (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                        :backend 'eas :format 'text :width 60 :person "alex"
                                        :marker "ldl-c"))
           (wide (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                      :backend 'eas :format 'text :width 110 :person "alex"
                                      :marker "ldl-c")))
      (should (<= (apply #'max (mapcar #'string-width (split-string narrow "\n"))) 60))
      (should (> (apply #'max (mapcar #'string-width (split-string wide "\n"))) 90))
      ;; each cell of a mark carries its datum: moving point is the terminal's hover
      (should (text-property-not-all 0 (length wide) 'help-echo nil wide)))))

(ert-deftest health-chart-eas-test-every-kind-draws-as-svg ()
  (health-chart-eas-test--when-eas
    (dolist (kind (health-chart-eas-test--kinds))
      (let ((svg (apply #'health-chart-render kind (health-chart-backend-test--data kind)
                        :backend 'eas :format 'svg (health-chart-eas-test--props kind))))
        (should (string-prefix-p "<svg" svg))
        (when (fboundp 'libxml-parse-xml-region)
          (should (with-temp-buffer (insert svg)
                                    (libxml-parse-xml-region (point-min) (point-max)))))
        ;; the words reach the drawing
        (should (string-match-p ">[^<]*\\(optimal\\|suboptimal\\|high\\|low\\|improved\\|worsened\\|fresh\\|due\\|stale\\|steady\\)"
                                svg))))))

(ert-deftest health-chart-eas-test-svg-size-follows-props ()
  (health-chart-eas-test--when-eas
    (let ((svg (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                    :backend 'eas :format 'svg :person "alex" :marker "ldl-c"
                                    :pixel-width 500 :pixel-height 300)))
      (should (string-match-p "width=\"500" svg)))))

(ert-deftest health-chart-eas-test-themes ()
  (health-chart-eas-test--when-eas
    (let ((light (health-chart-render 'bullet (health-chart-backend-test-sample)
                                      :backend 'eas :format 'svg :person "alex" :theme 'light))
          (dark (health-chart-render 'bullet (health-chart-backend-test-sample)
                                     :backend 'eas :format 'svg :person "alex" :theme 'dark)))
      (should (string-match-p "#fcfcfb" light))
      (should (string-match-p "#1a1a19" dark))
      (should-not (equal light dark)))))

(ert-deftest health-chart-eas-test-props-select-and-title ()
  (health-chart-eas-test--when-eas
    (let ((text (substring-no-properties
                 (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                      :backend 'eas :format 'text :person "sam" :marker "ldl-c"
                                      :title "Sam's LDL" :ref nil :optimal nil))))
      (should (string-match-p "Sam's LDL" text))
      (should-not (string-match-p "reference" text)))
    (should-error (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                       :backend 'eas :format 'text :marker "nope")
                  :type 'health-chart-invalid-data)
    ;; nothing selected: nothing to draw, not an error
    (should-not (health-chart-render 'delta nil :backend 'eas :format 'text))))

(ert-deftest health-chart-eas-test-delta-from-to ()
  (health-chart-eas-test--when-eas
    (let ((text (substring-no-properties
                 (health-chart-render 'delta (health-chart-backend-test-sample)
                                      :backend 'eas :format 'text :person "alex"
                                      :from "2024-01-15" :to "2025-09-15"))))
      (should (string-match-p "Change 2024-01-15 → 2025-09-15" text)))))

(ert-deftest health-chart-eas-test-write-svg-and-text-files ()
  (health-chart-eas-test--when-eas
    (let ((dir (make-temp-file "hc-eas" t)))
      (unwind-protect
          (progn
            (health-chart-write 'bullet (health-chart-backend-test-sample)
                                (expand-file-name "b.svg" dir) :backend 'eas :person "alex")
            (health-chart-write 'bullet (health-chart-backend-test-sample)
                                (expand-file-name "b.txt" dir) :backend 'eas :person "alex")
            (should (string-prefix-p "<svg" (health-chart-test-read-utf8 (expand-file-name "b.svg" dir))))
            (should (string-match-p "Latest vs range"
                                    (health-chart-test-read-utf8 (expand-file-name "b.txt" dir)))))
        (delete-directory dir t)))))

;; -----------------------------------------------------------------------
;; Parity with the kind's own numbers
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-templates-plot-the-kinds-own-numbers ()
  "Every template plots what `health-chart-spec' says the kind plots."
  (health-chart-eas-test--when-eas
    (dolist (kind (health-chart-eas-test--kinds))
      (let ((checks (apply #'health-chart-eas-parity kind (health-chart-backend-test--data kind)
                           (list (health-chart-eas-test--props kind)))))
        (should checks)
        (dolist (check checks)
          (should (equal (list kind (car check) t)
                         (list kind (car check)
                               (health-chart-eas--same-p (nth 1 check) (nth 2 check))))))))))

(ert-deftest health-chart-eas-test-parity-sees-a-wrong-number ()
  (health-chart-eas-test--when-eas
    (let* ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex"))
           (checks (health-chart-eas-parity 'timeseries ms (list :marker "ldl-c")))
           (changed (mapcar (lambda (c) (list (car c) (nth 1 c)
                                              (cons (cons 'x 1) (nth 2 c))))
                            checks)))
      (should (health-chart-eas-parity-ok-p checks))
      (should-not (health-chart-eas-parity-ok-p changed)))))

;; -----------------------------------------------------------------------
;; Selection, explain, the Vega-Lite export
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-selection ()
  (health-chart-eas-test--when-eas
    (cl-letf (((symbol-function 'health-chart-vega-lite-available-p) (lambda () t))
              ((symbol-function 'health-chart-gnuplot-available-p) (lambda () t))
              ((symbol-function 'health-chart--graphic-context-p) (lambda () t)))
      (should (equal (butlast (health-chart-select-backend 'timeseries)) '(eas svg)))
      ;; eas writes svg and text only: png goes to the next backend
      (should (equal (butlast (health-chart-select-backend 'timeseries nil 'png)) '(vega-lite png)))
      (should (equal (butlast (health-chart-select-backend 'timeseries nil 'text)) '(eas text)))
      ;; kinds with no eas template are not eas's
      (should (equal (butlast (health-chart-select-backend 'table)) '(text text)))
      (should (equal (butlast (health-chart-select-backend 'timeseries 'eas)) '(eas svg)))
      (let ((err (should-error (health-chart-select-backend 'table 'eas)
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "unsupported_kind")))
      (let ((err (should-error (health-chart-select-backend 'timeseries 'eas 'png)
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "unsupported_format"))))
    (cl-letf (((symbol-function 'health-chart--graphic-context-p) (lambda () nil)))
      (should (equal (butlast (health-chart-select-backend 'timeseries)) '(eas text))))))

(ert-deftest health-chart-eas-test-falls-through-without-eas ()
  (health-chart-eas-test--when-eas
    (cl-letf (((symbol-function 'health-chart-eas-available-p) (lambda () nil))
              ((symbol-function 'health-chart-vega-lite-available-p) (lambda () nil))
              ((symbol-function 'health-chart-gnuplot-available-p) (lambda () nil))
              ((symbol-function 'health-chart--graphic-context-p) (lambda () nil)))
      (should (equal (butlast (health-chart-select-backend 'timeseries)) '(text text)))
      (should-not (seq-some (lambda (tpl) (eq (plist-get tpl :backend) 'eas))
                            (health-chart-templates)))
      (let ((err (should-error (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                                    :backend 'eas :format 'text :person "alex")
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "backend_missing"))
        (should (string-match-p "eas.el" (cadr err)))))))

(ert-deftest health-chart-eas-test-explain-is-a-pure-plan ()
  (health-chart-eas-test--when-eas
    (let ((plan (health-chart-explain 'bullet (health-chart-backend-test-sample)
                                      :backend 'eas :format 'text :person "alex")))
      (should (eq (plist-get plan :valid) t))
      (should (eq (plist-get plan :backend) 'eas))
      (should (string-suffix-p "templates/eas/health-bullet.json" (plist-get plan :template)))
      (should-not (plist-get plan :steps))
      (let ((program (json-parse-string (plist-get plan :program) :object-type 'plist)))
        (should (equal (plist-get program :$schema) "https://vega.github.io/schema/vega-lite/v6.json"))
        (should-not (plist-member program :x-eas))))))

(ert-deftest health-chart-eas-test-vega-lite-export ()
  "The vega-lite backend draws an eas kind from its resolved template."
  (health-chart-eas-test--when-eas
    (let* ((json (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                      :backend 'vega-lite :format 'vega-lite :person "alex"
                                      :marker "ldl-c"))
           (spec (json-parse-string json :object-type 'plist)))
      (should (equal (plist-get spec :width) 720))
      (should (plist-get spec :layer))
      (should-not (string-match-p "x-eas" json))
      ;; a user template of the same kind still wins
      (health-chart-backend-test-with-templates dir
        (health-chart-backend-test--write (expand-file-name "vega-lite/timeseries.vl.json" dir)
                                          "{\"mine\": {{title}}}")
        (should (equal (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                            :backend 'vega-lite :format 'vega-lite :person "alex"
                                            :marker "ldl-c")
                       "{\"mine\": \"LDL-C · alex\"}"))))))

(ert-deftest health-chart-eas-test-vega-lite-export-draws ()
  (health-chart-eas-test--when-eas
    (skip-unless (health-chart-vega-lite-available-p))
    (let ((svg (health-chart-render 'bullet (health-chart-backend-test-sample)
                                    :backend 'vega-lite :format 'svg :person "alex")))
      (should (string-prefix-p "<svg" svg))
      (should (string-match-p "optimal" svg)))))

;; -----------------------------------------------------------------------
;; Live views
;; -----------------------------------------------------------------------

(ert-deftest health-chart-eas-test-live-view ()
  (health-chart-eas-test--when-eas
    (let ((view (health-chart-eas-view 'timeseries (health-chart-backend-test-sample)
                                       (list :person "alex" :marker "ldl-c") 'text)))
      (unwind-protect
          (progn
            (should (equal (eas-view-template view) "health-timeseries"))
            (should (member (eas-view-id view) (eas-view-ids)))
            (require 'eas-agent)
            (let ((inspect (eas-agent "inspect" (eas-view-id view))))
              (should (eq (plist-get inspect :ok) t))))
        (eas-view-close view)))
    (should-not (health-chart-eas-view 'delta nil))))

(ert-deftest health-chart-eas-test-doctor-covers-the-eas-backend ()
  (health-chart-eas-test--when-eas
    (let ((rows (health-chart-render-doctor-checks)))
      (should (seq-find (lambda (r) (and (equal (plist-get r :name) "backend eas")
                                         (eq (plist-get r :status) 'pass)))
                        rows))
      (dolist (kind (health-chart-eas-test--kinds))
        (let ((row (seq-find (lambda (r) (equal (plist-get r :name) (format "template eas/%s" kind)))
                             rows)))
          (should row)
          (should (eq (plist-get row :status) 'pass)))))))

(provide 'health-chart-eas-test)
;;; health-chart-eas-test.el ends here

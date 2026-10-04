;;; health-chart-gallery-test.el --- The gallery chart kinds -*- lexical-binding: t; -*-

;; trend, lollipop, strip, dumbbell, dual and inrange (docs/chart-gallery.md):
;; what their specs derive, that no status is color alone, that they are
;; drawn by templates only and fall back cleanly, and that they render.
;; The per-kind spec and program goldens live in health-chart-backend-test.el.

;;; Code:

(require 'health-chart-test-helpers)
;; Shares the sample and golden props of health-chart-backend-test.el, which
;; `make test' loads first (the test files load in name order).
(defvar health-chart-backend-test--specs)
(declare-function health-chart-backend-test-sample "health-chart-backend-test" ())
(declare-function health-chart-backend-test--png-p "health-chart-backend-test" (bytes))
(declare-function health-chart-backend-test--write "health-chart-backend-test" (file text))
(defvar health-chart-backend-test-with-templates)

(defconst health-chart-gallery-test--kinds
  '(trend lollipop strip dumbbell dual inrange)
  "The gallery kinds.")

(defun health-chart-gallery-test--spec (kind &rest props)
  "The spec of KIND over the sample panel under PROPS (alex by default)."
  (apply #'health-chart-spec kind (health-chart-backend-test-sample)
         (append props
                 (cdr (assq kind health-chart-backend-test--specs)))))

(defun health-chart-gallery-test--rows (spec)
  "SPEC's rows as a list."
  (append (plist-get spec :rows) nil))

(defun health-chart-gallery-test--series (values)
  "Measurements of one marker, alex, one per month with VALUES."
  (cl-loop for v in values for i from 1
           collect (health-chart-source-normalize
                    (list :person "alex" :marker "x" :value v :unit "u"
                          :date (format "2025-%02d-01" i)
                          :ref-low 0 :ref-high 10 :opt-high 5))))

;; -----------------------------------------------------------------------
;; Registry
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-kinds-are-registered-template-only ()
  (health-chart-test-env
    (dolist (kind health-chart-gallery-test--kinds)
      (let ((entry (alist-get kind health-chart-kinds)))
        (should entry)
        (should (plist-get entry :doc))
        (should (plist-get entry :spec))
        (should-not (plist-get entry :text))
        (should-not (plist-get entry :svg)))
      (should (health-chart-template-for 'vega-lite kind))
      (should (health-chart-template-for 'gnuplot kind))
      (should (plist-get (health-chart-describe-kind kind) :renderers-defined))
      (should (equal (plist-get (health-chart-describe-kind kind) :templates)
                     '(vega-lite gnuplot))))))

(ert-deftest health-chart-gallery-test-native-backends-decline-cleanly ()
  (health-chart-test-env
    (dolist (backend '(text svg))
      (let ((err (should-error (health-chart-render-string 'strip (health-chart-backend-test-sample)
                                                           :backend backend :person "alex")
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "unsupported_kind"))
        (should (string-match-p "templates only; use vega-lite or gnuplot" (cadr err)))))
    ;; auto in a terminal with no template backend names the fix too
    (let ((health-chart-terminal-backends '(text)))
      (let ((err (should-error (health-chart-select-backend 'strip)
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "no_backend"))))))

(ert-deftest health-chart-gallery-test-vega-lite-only-kind-falls-back ()
  "A kind with just a vega-lite template draws there and declines other backends."
  (health-chart-test-env
    (health-chart-backend-test-with-templates dir
      (health-chart-backend-test--write
       (expand-file-name "vega-lite/solo.vl.json" dir)
       "{\"width\": {{width}}, \"data\": {\"values\": {{data}}}, \"mark\": \"point\"}")
      (should (health-chart-template-for 'vega-lite 'solo))
      (should-not (health-chart-template-for 'gnuplot 'solo))
      (cl-letf (((symbol-function 'health-chart-vega-lite-available-p) (lambda () t))
                ((symbol-function 'health-chart-gnuplot-available-p) (lambda () t))
                ((symbol-function 'health-chart--graphic-context-p) (lambda () t)))
        (should (equal (butlast (health-chart-select-backend 'solo)) '(vega-lite svg)))
        (let ((health-chart-graphic-backends '(gnuplot vega-lite)))
          (should (equal (butlast (health-chart-select-backend 'solo)) '(vega-lite svg))))
        (let ((health-chart-terminal-backends '(gnuplot text)))
          (should-error (health-chart-select-backend 'solo nil 'text)
                        :type 'health-chart-backend-error))
        (let ((err (should-error (health-chart-render-string 'solo (health-chart-test-ms)
                                                             :backend 'gnuplot :format 'svg)
                                 :type 'health-chart-backend-error)))
          (should (equal (plist-get (cddr err) :code) "no_template")))))))

(ert-deftest health-chart-gallery-test-specs-have-no-duplicate-members ()
  "A row or object naming a member twice would encode as duplicate JSON keys."
  (health-chart-test-env
    (dolist (kind health-chart-gallery-test--kinds)
      (let ((spec (health-chart-gallery-test--spec kind)))
        (dolist (obj (cons spec (append (health-chart-gallery-test--rows spec)
                                        (append (plist-get spec :legend) nil))))
          (let ((keys (cl-loop for (k) on obj by #'cddr collect k)))
            (should (equal keys (delete-dups (copy-sequence keys))))))))))

;; -----------------------------------------------------------------------
;; Status is never color alone
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-every-colored-thing-has-a-word-and-glyph ()
  (health-chart-test-env
    (dolist (kind health-chart-gallery-test--kinds)
      (let* ((spec (health-chart-gallery-test--spec kind))
             (legend (append (plist-get spec :legend) nil)))
        (should legend)
        (dolist (entry legend)
          (should (> (length (plist-get entry :glyph)) 0))
          (should (> (length (plist-get entry :word)) 0))
          (should (string-match-p (regexp-quote (plist-get entry :word))
                                  (plist-get entry :label)))
          (should (string-match-p (regexp-quote (plist-get entry :glyph))
                                  (plist-get entry :label))))
        ;; every row's color is explained by a legend entry of the same color
        (let ((colors (mapcar (lambda (e) (plist-get e :color)) legend)))
          (dolist (row (health-chart-gallery-test--rows spec))
            (when (and (plist-get row :latest) (= 1 (plist-get row :latest)))
              (should (member (or (plist-get row :verdict_color) (plist-get row :color)) colors)))))))))

;; -----------------------------------------------------------------------
;; Range position (strip, dumbbell)
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-range-position-math ()
  (should (equal (health-chart-spec-gallery--scale '(:ref-low 0 :ref-high 100)) '(0 . 100)))
  (should (equal (health-chart-spec-gallery--scale '(:ref-high 3.0)) '(0 . 3.0)))
  ;; open high side: low edge plus twice the distance to the optimal low edge
  (should (equal (health-chart-spec-gallery--scale '(:ref-low 40 :opt-low 60)) '(40 . 80)))
  (should (equal (health-chart-spec-gallery--scale '(:opt-low 10 :opt-high 20)) '(10 . 20)))
  (should-not (health-chart-spec-gallery--scale nil))
  (should (= 0.25 (health-chart-spec-gallery--norm 25 '(0 . 100))))
  (should (= -0.5 (health-chart-spec-gallery--norm 30 '(40 . 60))))
  (should (equal (health-chart-spec-gallery--norm-domain '(0.2 0.8)) '(-0.25 . 1.25)))
  (should (equal (health-chart-spec-gallery--norm-domain '(-5 9)) '(-2.0 . 3.0))))

(ert-deftest health-chart-gallery-test-strip-rows ()
  (health-chart-test-env
    (let* ((spec (health-chart-gallery-test--spec 'strip))
           (rows (health-chart-gallery-test--rows spec))
           (latest (seq-filter (lambda (r) (= 1 (plist-get r :latest))) rows))
           (ldl (seq-find (lambda (r) (and (equal (plist-get r :marker) "ldl-c")
                                           (= 1 (plist-get r :latest))))
                          rows)))
      (should (= (length latest) 13))
      (should (= 13 (length (plist-get (plist-get spec :y) :domain))))
      ;; LDL-C 76 on 0..100
      (should (= 0.76 (plist-get ldl :norm)))
      (should (= 0 (plist-get ldl :clipped)))
      (should (equal (plist-get ldl :latest_label) "76 mg/dL  ◐ suboptimal"))
      ;; every row inside the display domain, its true position kept in norm
      (let ((dom (plist-get (plist-get spec :x) :domain)))
        (dolist (r rows)
          (should (<= (aref dom 0) (plist-get r :x) (aref dom 1)))))
      ;; Lp(a), far above its range, is clamped only if outside the domain
      (let ((lpa (seq-find (lambda (r) (and (equal (plist-get r :marker) "lpa")
                                            (= 1 (plist-get r :latest))))
                           rows)))
        (should (> (plist-get lpa :norm) 1.5))))))

(ert-deftest health-chart-gallery-test-dumbbell-rows ()
  (health-chart-test-env
    (let* ((spec (health-chart-gallery-test--spec 'dumbbell))
           (rows (health-chart-gallery-test--rows spec))
           (ldl (seq-find (lambda (r) (equal (plist-get r :marker) "ldl-c")) rows))
           (lpa (seq-find (lambda (r) (equal (plist-get r :marker) "lpa")) rows)))
      (should (= (length rows) 13))
      (should (= 1.62 (plist-get ldl :norm_before)))
      (should (= 0.76 (plist-get ldl :norm_after)))
      (should (equal (plist-get ldl :verdict) "improved"))
      (should (equal (plist-get ldl :verdict_label) "✔ improved"))
      (should (equal (plist-get ldl :values_label) "162 → 76 mg/dL"))
      (should (equal (plist-get lpa :verdict) "worsened"))
      (should (equal (plist-get lpa :verdict_glyph) "✖"))
      (should (equal (plist-get ldl :date_before) "2021-11-08"))
      (should (equal (plist-get ldl :date_after) "2025-09-15"))
      ;; the legend names exactly the verdicts present
      (should (equal (mapcar (lambda (e) (plist-get e :key)) (plist-get spec :legend))
                     '("improved" "on-target" "worsened"))))))

(ert-deftest health-chart-gallery-test-dumbbell-needs-two-draws ()
  (health-chart-test-env
    (let ((one (list (car (health-chart-gallery-test--series '(1 2))))))
      (should (= 0 (length (plist-get (health-chart-spec 'dumbbell one) :rows)))))))

;; -----------------------------------------------------------------------
;; inrange
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-inrange-segments-tile-each-bar ()
  (health-chart-test-env
    (let* ((spec (health-chart-gallery-test--spec 'inrange))
           (rows (health-chart-gallery-test--rows spec))
           (by (seq-group-by (lambda (r) (plist-get r :index)) rows)))
      (should (= 13 (length by)))
      (pcase-dolist (`(,_ . ,segs) by)
        (should (= 1 (plist-get (car (last segs)) :x2)))
        (should (= 0 (plist-get (car segs) :x)))
        (should (= (plist-get (car segs) :draws)
                   (apply #'+ (mapcar (lambda (s) (plist-get s :count)) segs))))
        (cl-loop for (a b) on segs while b do (should (= (plist-get a :x2) (plist-get b :x)))))
      ;; worst first: Lp(a) has no draw in range
      (should (equal (aref (plist-get (plist-get spec :y) :domain) 0) "Lp(a)"))
      (should (equal (plist-get (car rows) :summary) "0/8 in range")))))

(ert-deftest health-chart-gallery-test-inrange-orders-low-inside-high ()
  (health-chart-test-env
    (let* ((ms (append (health-chart-gallery-test--series '(-1 3 7 12 3)) nil))
           (rows (health-chart-gallery-test--rows (health-chart-spec 'inrange ms))))
      (should (equal (mapcar (lambda (r) (plist-get r :status)) rows)
                     '("low" "optimal" "suboptimal" "high")))
      (should (equal (mapcar (lambda (r) (plist-get r :count)) rows) '(1 2 1 1))))))

;; -----------------------------------------------------------------------
;; trend and lollipop
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-linear-fit ()
  (should-not (health-chart-spec-gallery--fit '(1 2) '(1 2)))
  (pcase-let ((`(,slope ,dm ,vm) (health-chart-spec-gallery--fit '(0 10 20) '(5 15 25))))
    (should (= slope 1.0))
    (should (= dm 10.0))
    (should (= vm 15.0))))

(ert-deftest health-chart-gallery-test-trend-rows ()
  (health-chart-test-env
    (let* ((spec (health-chart-gallery-test--spec 'trend))
           (rows (health-chart-gallery-test--rows spec))
           (trend (plist-get (plist-get spec :layout) :trend)))
      (should (= 8 (length rows)))
      (should (< (plist-get trend :slope_per_year) -20))
      (should (string-match-p "↘ falling .* mg/dL per year" (plist-get trend :label)))
      (should (string-match-p "falling" (plist-get spec :subtitle)))
      ;; rolling mean of the first two draws (162, 151) and of the middle three
      (should (= 156.5 (plist-get (nth 0 rows) :roll)))
      (should (< (abs (- (/ (+ 151 138 121) 3.0) (plist-get (nth 2 rows) :roll))) 0.001))
      ;; the fit is one straight line
      (let ((slope (/ (- (plist-get (nth 7 rows) :fit) (plist-get (nth 0 rows) :fit))
                      (float (- (health-chart-date-days (plist-get (nth 7 rows) :date))
                                (health-chart-date-days (plist-get (nth 0 rows) :date)))))))
        (should (< (abs (- (* 365.25 slope) (plist-get trend :slope_per_year))) 0.05))))))

(ert-deftest health-chart-gallery-test-trend-flat-and-short ()
  (health-chart-test-env
    (let* ((flat (health-chart-spec 'trend (health-chart-gallery-test--series '(5 5 5 5))))
           (short (health-chart-spec 'trend (health-chart-gallery-test--series '(5 6)))))
      (should (string-match-p "→ flat" (plist-get (plist-get (plist-get flat :layout) :trend) :label)))
      (should (equal (plist-get (plist-get (plist-get short :layout) :trend) :label)
                     "trend needs three draws"))
      (should-not (plist-get (aref (plist-get short :rows) 0) :fit)))))

(ert-deftest health-chart-gallery-test-lollipop-stems-run-to-the-limit ()
  (health-chart-test-env
    (let* ((spec (health-chart-gallery-test--spec 'lollipop))
           (rows (health-chart-gallery-test--rows spec))
           (first (car rows)) (last (car (last rows)))
           (th (aref (plist-get (plist-get spec :overlays) :thresholds) 0)))
      ;; hs-CRP: optimal ≤1.0, first draw 4.2, latest 0.8
      (should (= 1 (plist-get first :base)))
      (should (= 3.2 (plist-get first :gap)))
      (should (equal (plist-get first :gap_label) "+3.2"))
      (should (equal (plist-get last :gap_label) "−0.2"))
      (should (= 1 (plist-get th :value)))
      (should (string-match-p "optimal limit 1 mg/L" (plist-get th :label)))
      ;; the y domain holds the limit and leaves room for the tallest label
      (let ((dom (plist-get (plist-get spec :y) :domain)))
        (should (< (aref dom 0) 0.8))
        (should (> (aref dom 1) 4.2))))))

;; -----------------------------------------------------------------------
;; dual
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-dual-axes-and-rows ()
  (health-chart-test-env
    (let* ((spec (health-chart-gallery-test--spec 'dual))
           (rows (health-chart-gallery-test--rows spec))
           (layout (plist-get spec :layout))
           (ths (append (plist-get (plist-get spec :overlays) :thresholds) nil)))
      (should (= 16 (length rows)))
      (should (equal (mapcar (lambda (r) (plist-get r :axis)) (seq-take rows 1)) '("left")))
      (should (= 8 (length (seq-filter (lambda (r) (equal (plist-get r :axis) "right")) rows))))
      (should (equal (plist-get (plist-get layout :left) :title) "Glucose (mg/dL)"))
      (should (equal (plist-get (plist-get layout :right) :title) "HbA1c (%)"))
      (should-not (equal (plist-get (plist-get layout :left) :color)
                         (plist-get (plist-get layout :right) :color)))
      ;; each marker's own domain: glucose in the 100s, HbA1c under 10
      (should (> (aref (plist-get (plist-get layout :left) :domain) 1) 100))
      (should (< (aref (plist-get (plist-get layout :right) :domain) 1) 10))
      (should (equal (mapcar (lambda (th) (plist-get th :label)) ths) '("Glucose ≤99" "HbA1c ≤5.6")))
      (should (equal (mapcar (lambda (th) (plist-get th :axis)) ths) '("left" "right")))
      (should (string-match-p "Glucose 89 mg/dL .*optimal" (plist-get spec :subtitle))))))

(ert-deftest health-chart-gallery-test-dual-picks-and-checks-markers ()
  (health-chart-test-env
    (let ((ms (health-chart-backend-test-sample)))
      (should (equal (health-chart-spec-gallery--dual-markers ms nil) '("glucose" "hba1c")))
      (should (equal (health-chart-spec-gallery--dual-markers ms '(:marker ("tsh" "alt"))) '("tsh" "alt")))
      (should (eq t (health-chart-validate 'dual ms :marker '("tsh" "alt"))))
      (let ((err (should-error (health-chart-validate 'dual ms :marker '("tsh" "nope"))
                               :type 'health-chart-invalid-data)))
        (should (equal (plist-get (cddr err) :code) "unknown_marker")))
      (let ((err (should-error (health-chart-validate 'dual ms :marker '("tsh" "alt" "ldl-c"))
                               :type 'health-chart-invalid-data)))
        (should (equal (plist-get (cddr err) :code) "invalid_prop")))
      (should-error (health-chart-validate 'dual (health-chart-filter ms :marker "tsh"))
                    :type 'health-chart-invalid-data))))

;; -----------------------------------------------------------------------
;; Rendering, when the tools are installed
;; -----------------------------------------------------------------------

(ert-deftest health-chart-gallery-test-vega-lite-draws-words-not-just-colors ()
  (skip-unless (health-chart-vega-lite-available-p))
  (health-chart-test-env
    (dolist (kind health-chart-gallery-test--kinds)
      (let ((svg (apply #'health-chart-render kind (health-chart-backend-test-sample)
                        :backend 'vega-lite :format 'svg
                        (cdr (assq kind health-chart-backend-test--specs)))))
        (should (string-prefix-p "<svg" svg))
        (should (string-match-p "alex\\|Glucose" svg))
        (should (string-match-p (if (eq kind 'dumbbell) "improved" "optimal") svg))))))

(ert-deftest health-chart-gallery-test-gnuplot-draws-every-format ()
  (skip-unless (health-chart-gnuplot-available-p))
  (health-chart-test-env
    (dolist (kind health-chart-gallery-test--kinds)
      (let ((props (cdr (assq kind health-chart-backend-test--specs))))
        (should (string-match-p "<svg" (apply #'health-chart-render kind (health-chart-backend-test-sample)
                                              :backend 'gnuplot :format 'svg props)))
        (let ((text (apply #'health-chart-render kind (health-chart-backend-test-sample)
                           :backend 'gnuplot :format 'text props)))
          (should (stringp text))
          (should (string-match-p "alex\\|Glucose" text)))))))

(ert-deftest health-chart-gallery-test-write-png-for-every-kind ()
  (skip-unless (and (health-chart-gnuplot-available-p) (health-chart-vega-lite-available-p)
                    (health-chart--rsvg-available-p)))
  (health-chart-test-env
    (let ((dir (make-temp-file "hc-gallery" t))
          (health-chart-vega-lite-raster 'rsvg-convert))
      (unwind-protect
          (dolist (kind health-chart-gallery-test--kinds)
            (dolist (backend '(vega-lite gnuplot))
              (let ((file (expand-file-name (format "%s-%s.png" backend kind) dir)))
                (apply #'health-chart-write kind (health-chart-backend-test-sample) file
                       :backend backend (cdr (assq kind health-chart-backend-test--specs)))
                (should (health-chart-backend-test--png-p (health-chart--read-bytes file))))))
        (delete-directory dir t)))))

(provide 'health-chart-gallery-test)
;;; health-chart-gallery-test.el ends here

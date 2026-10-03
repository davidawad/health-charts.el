;;; health-chart-render-test.el --- Text and SVG output of every kind -*- lexical-binding: t; -*-

;; Golden files pin the exact output of every kind in both backends
;; under `health-chart-test-env'.  Regenerate with
;; HEALTH_CHART_UPDATE_GOLDEN=1 make test and review the diff.

;;; Code:

(require 'health-chart-test-helpers)
(require 'dom)

(defconst health-chart-render-test--specs
  '((timeseries :person "alex" :marker "ldl_c")
    (panel :person "alex" :marker ("ldl_c" "hdl_c" "vitamin_d" "crp"))
    (table :person "alex")
    (bullet :person "alex")
    (heatmap :person "alex")
    (compare :marker "vitamin_d")
    (delta :person "alex"))
  "Each measurement kind with the props its golden files are rendered with.")

(ert-deftest health-chart-render-test-text-goldens ()
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-render-test--specs)
      (health-chart-test-golden
       (format "%s.txt" kind)
       (apply #'health-chart-plot kind (health-chart-test-ms) :backend 'text props)))
    (health-chart-test-golden
     "sparkline.txt" (health-chart-plot 'sparkline '(131 124 108 96 112 88) :backend 'text))))

(ert-deftest health-chart-render-test-svg-goldens ()
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-render-test--specs)
      (health-chart-test-golden
       (format "%s.svg" kind)
       (apply #'health-chart-plot kind (health-chart-test-ms) :backend 'svg props)))))

(ert-deftest health-chart-render-test-svg-is-well-formed-with-hover-titles ()
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-render-test--specs)
      (let ((svg (apply #'health-chart-plot kind (health-chart-test-ms) :backend 'svg props)))
        (should (string-prefix-p "<svg" svg))
        (should (string-match-p (format "<desc>health-chart %s: " kind) svg))
        (when (fboundp 'libxml-parse-xml-region)
          (let ((dom (with-temp-buffer (insert svg)
                                       (libxml-parse-xml-region (point-min) (point-max)))))
            (should (eq (dom-tag dom) 'svg))
            ;; a <desc>, a document <title>, and hover titles on the marks
            (should (> (length (dom-by-tag dom 'title)) 2))))))))

(ert-deftest health-chart-render-test-svg-provenance-escapes-title ()
  (health-chart-test-env
    (let ((svg (health-chart-plot 'timeseries (health-chart-test-ms "alex") :backend 'svg
                                  :title "LDL <trend> & co")))
      (should (string-match-p "<title>LDL &lt;trend&gt; &amp; co</title>" svg))
      (should (string-match-p "<desc>health-chart timeseries: 54 measurements, 2024-03-04 to 2025-06-02</desc>" svg)))))

(ert-deftest health-chart-render-test-svg-dark-theme ()
  (health-chart-test-env
    (let ((light (health-chart-plot 'table (health-chart-test-ms "alex") :backend 'svg))
          (dark (let ((health-chart-svg-theme 'dark))
                  (health-chart-plot 'table (health-chart-test-ms "alex") :backend 'svg))))
      (should (string-match-p "#fcfcfb" light))
      (should (string-match-p "#1a1a19" dark))
      (should-not (string-match-p "#fcfcfb" dark)))
    (let ((health-chart-svg-colors '((surface . "#123456"))))
      (should (string-match-p "#123456" (health-chart-plot 'bullet (health-chart-test-ms "alex") :backend 'svg))))))

(ert-deftest health-chart-render-test-band-glyphs-follow-toggles ()
  (health-chart-test-env
    (let ((ms (health-chart-test-ms "alex")))
      (let ((both (health-chart-plot 'timeseries ms :backend 'text)))
        (should (string-search "░" both))
        (should (string-search "▒" both)))
      (let ((no-ref (health-chart-plot 'timeseries ms :backend 'text :ref nil)))
        (should-not (string-search "░" no-ref))
        (should (string-search "▒" no-ref)))
      (let ((none (health-chart-plot 'timeseries ms :backend 'text :ref nil :optimal nil)))
        (should-not (string-search "░" none))
        (should-not (string-search "▒" none))
        (should-not (string-search "reference" none))))))

(ert-deftest health-chart-render-test-text-dimensions ()
  (health-chart-test-env
    (let* ((out (health-chart-plot 'timeseries (health-chart-test-ms "alex") :backend 'text
                                   :width 60 :height 8))
           (lines (split-string out "\n")))
      ;; title, 8 plot rows, axis, dates, legend
      (should (= 12 (length lines)))
      (should (cl-every (lambda (l) (<= (string-width l) 60)) lines)))))

(ert-deftest health-chart-render-test-table-rows-carry-marker-properties ()
  (health-chart-test-env
    (let ((out (health-chart-plot 'table (health-chart-test-ms) :backend 'text :person "sam"))
          markers)
      (dotimes (i (length out))
        (when-let* ((m (get-text-property i 'health-chart-marker out)))
          (unless (member m markers) (push m markers))
          (should (equal (get-text-property i 'health-chart-person out) "sam"))))
      (should (equal (nreverse markers) (health-chart-markers (health-chart-test-ms "sam")))))))

(ert-deftest health-chart-render-test-status-never-color-alone ()
  ;; every row's status shows a glyph and a word in plain text
  (health-chart-test-env
    (let ((out (substring-no-properties (health-chart-plot 'table (health-chart-test-ms) :backend 'text
                                                           :person "alex"))))
      (should (string-match-p "◐ suboptimal" out))
      (should (string-match-p "▲ high" out))
      (should (string-match-p "● optimal" out)))))

(ert-deftest health-chart-render-test-empty-data-renders-nothing ()
  (health-chart-test-env
    (dolist (kind '(timeseries panel table bullet heatmap compare delta))
      (dolist (backend '(text svg))
        (should-not (health-chart-plot kind nil :backend backend))))
    (should-not (health-chart-plot 'sparkline nil :backend 'text))
    (should (equal (health-chart-sparkline nil) ""))))

(ert-deftest health-chart-render-test-single-draw ()
  (health-chart-test-env
    (let ((one (list (health-chart-test-m :ref-low 0 :ref-high 130))))
      (dolist (kind '(timeseries panel table bullet heatmap compare))
        (should (stringp (health-chart-plot kind one :backend 'text)))
        (should (stringp (health-chart-plot kind one :backend 'svg))))
      (should-not (health-chart-plot 'delta one :backend 'text)))))

(ert-deftest health-chart-render-test-plain-lisp-alists ()
  ;; charts take JSON-style alists straight from Lisp, no CLI involved
  (health-chart-test-env
    (let ((data '(((marker . "glucose") (value . 92) (date . "2025-01-10") (ref_low . 70) (ref_high . 99))
                  ((marker . "glucose") (value . 104) (date . "2025-04-10") (ref_low . 70) (ref_high . 99)))))
      (should (string-match-p "▲ high"
                              (substring-no-properties
                               (health-chart-plot 'timeseries data :backend 'text)))))))

;;; health-chart-render-test.el ends here

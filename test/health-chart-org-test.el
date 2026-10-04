;;; health-chart-org-test.el --- Tests for the Org report layer -*- lexical-binding: t; -*-

;;; Commentary:

;; Dynamic block output (golden Org text over a fake source), template
;; stamping, the explain twins, and an export smoke test when the image
;; tools are installed.  Synthetic data only.

;;; Code:

(require 'health-chart-org-test-helpers)
(require 'ox-html)
(require 'ox-latex)

(defconst health-chart-org-test--doc
  "* Report
#+BEGIN: health-flags :person \"alex\" :until \"2025-09-30\"
#+END:
#+BEGIN: health-table :person \"alex\" :category \"lipids\" :until \"2025-09-30\"
#+END:
#+BEGIN: health-scorecard :person \"alex\" :cohort (cardio metabolic) :as-of \"2025-10-01\"
#+END:
#+BEGIN: health-chart :kind scorecard :cohort vitamins :person \"alex\" :as-of \"2025-10-01\" :caption \"Vitamins\"
#+END:
#+BEGIN: health-chart :kind bullet :person \"alex\" :category \"metabolic\" :backend text
#+END:
#+BEGIN: health-chart :kind bogus
#+END:
#+BEGIN: health-chart :person \"alex\" :since \"last year\"
#+END:
#+BEGIN: health-scorecard :person \"alex\"
#+END:
#+BEGIN: health-genetics :section apoe :kit \"demo\"
#+END:
#+BEGIN: health-genetics :section ancestry
#+END:
"
  "A document using every block without image tools.")

(ert-deftest health-chart-org-test-blocks-golden ()
  (health-chart-org-test-env
    (health-chart-test-golden "org-blocks.org"
                              (health-chart-org-test-update health-chart-org-test--doc))))

(ert-deftest health-chart-org-test-refresh-is-idempotent ()
  (health-chart-org-test-env
    (let ((once (health-chart-org-test-update health-chart-org-test--doc)))
      (should (equal once (health-chart-org-test-update once))))))

(ert-deftest health-chart-org-test-errors-never-break-the-document ()
  (health-chart-org-test-env
    (let ((health-chart-source-function
           (lambda (&rest _) (signal 'health-chart-source-error
                                     (list "cannot find biomarker; install biomarker-cli"
                                           :code "source_missing")))))
      (let ((out (health-chart-org-test-update
                  "#+BEGIN: health-table :person \"alex\"\n#+END:\nafter\n")))
        (should (string-match-p
                 "^# health-table (source_missing): cannot find biomarker; install biomarker-cli$"
                 out))
        (should (string-match-p "^after$" out))))))

(ert-deftest health-chart-org-test-genetics-delegates-by-name ()
  (health-chart-org-test-env
    (let (got)
      (cl-letf (((symbol-function 'org-dblock-write:genetics-hits)
                 (lambda (params) (setq got params) (insert "| rs0000 | demo |"))))
        (let ((out (health-chart-org-test-update
                    "#+BEGIN: health-genetics :section hits :file \"kit.txt\"\n#+END:\n")))
          (should (string-match-p "^| rs0000 | demo |$" out))
          (should (equal (plist-get got :file) "kit.txt"))
          (should-not (plist-member got :section)))))))

(ert-deftest health-chart-org-test-flags-when-all-in-range ()
  (health-chart-org-test-env
    (should (string-match-p
             "^- ● optimal No markers out of range\\.$"
             (health-chart-org-test-update
              "#+BEGIN: health-flags :person \"alex\" :markers (\"tsh\" \"alt\")\n#+END:\n")))))

;; -----------------------------------------------------------------------
;; Explain twins
;; -----------------------------------------------------------------------

(ert-deftest health-chart-org-test-explain-is-pure ()
  (health-chart-org-test-env
    (let ((health-chart-source-function (lambda (&rest _) (error "Explain fetched data")))
          (org (expand-file-name "notes/report.org")))
      (let ((plan (health-chart-org-chart-explain
                   '(:kind timeseries :person "alex" :marker "ldl-c" :since "2024-01-01")
                   org)))
        (should (eq (plist-get plan :valid) t))
        (should (eq (plist-get plan :mode) 'image))
        (should (eq (plist-get plan :format) 'svg))
        (should (equal (plist-get (plist-get plan :query) :command) 'trend))
        (should (equal (plist-get (plist-get plan :query) :args)
                       '(:person "alex" :marker "ldl-c" :since "2024-01-01")))
        (should (string-match-p "/notes/report-assets/timeseries-alex-ldl-c-[0-9a-f]\\{8\\}\\.svg\\'"
                                (plist-get plan :output)))
        (should (string-prefix-p "report-assets/" (plist-get plan :link))))
      ;; same params, same file; different params, different file
      (let ((a (plist-get (health-chart-org-chart-explain '(:kind panel :person "alex") org) :output))
            (b (plist-get (health-chart-org-chart-explain '(:kind panel :person "alex") org) :output))
            (c (plist-get (health-chart-org-chart-explain '(:kind panel :person "sam") org) :output)))
        (should (equal a b))
        (should-not (equal a c)))
      (should (string-suffix-p ".png" (plist-get (health-chart-org-chart-explain
                                                  '(:kind panel :format png) org)
                                                 :output)))
      (should (equal (plist-get (health-chart-org-chart-explain '(:kind panel :file "x/y.svg") org)
                                :output)
                     (expand-file-name "notes/x/y.svg")))
      (let ((plan (health-chart-org-table-explain '(:person "alex" :markers ("apob" "lpa")))))
        (should (eq (plist-get (plist-get plan :query) :command) 'latest))
        (should (equal (plist-get (plist-get (plist-get plan :query) :filter) :marker) '("apob" "lpa")))
        (should (string-prefix-p "#+PLOT:" (plist-get plan :plot))))
      (let ((plan (health-chart-org-scorecard-explain '(:cohort cardio :person "alex"))))
        (should (eq (plist-get plan :valid) t))
        (should (equal (plist-get (plist-get plan :query) :cohorts) '(cardio))))
      (should (stringp (plist-get (health-chart-org-scorecard-explain '(:cohort nope)) :valid)))
      (should (stringp (plist-get (health-chart-org-chart-explain '(:until "soon")) :valid)))
      (let ((plan (health-chart-org-genetics-explain '(:section apoe :kit "demo"))))
        (should (eq (plist-get plan :delegate) 'org-dblock-write:genetics-apoe))
        (should (equal (plist-get plan :args) '(:kit "demo"))))
      (should (equal (plist-get (health-chart-org-explain "health-flags" '(:person "alex")) :block)
                  "health-flags"))
      (should-error (health-chart-org-explain "health-nope" nil) :type 'health-chart-org-error)
      (should-not health-chart-org-test-calls))))

(ert-deftest health-chart-org-test-explain-block-at-point ()
  (health-chart-org-test-env
    (with-temp-buffer
      (insert "#+BEGIN: health-chart :kind heatmap :person \"alex\"\n#+END:\n")
      (goto-char (point-min))
      (forward-line 1)
      (let ((plan (health-chart-org-explain-block)))
        (should (eq (plist-get plan :kind) 'heatmap))))))

(ert-deftest health-chart-org-test-new-report-explain ()
  (health-chart-org-test-env
    (let* ((health-chart-source-function (lambda (&rest _) (error "Explain fetched data")))
           (plan (health-chart-org-new-report-explain "lab-draw" "out/draw.org"
                                                      :person "alex" :date "2025-10-01")))
      (should (equal (plist-get (plist-get plan :context) :since) "2024-10-01"))
      (should (string-suffix-p "/out/draw-assets/" (plist-get plan :assets)))
      (should (cl-every (lambda (b) (eq (plist-get b :valid) t)) (plist-get plan :blocks)))
      (should (= 7 (length (plist-get plan :blocks)))))))

;; -----------------------------------------------------------------------
;; Templates
;; -----------------------------------------------------------------------

(ert-deftest health-chart-org-test-templates-listed ()
  (should (equal (mapcar (lambda (tpl) (plist-get tpl :name)) (health-chart-org-template-list))
                 '("annual-review" "cardiometabolic" "full-health-report" "genetics-summary"
                   "lab-draw")))
  (should (cl-every (lambda (tpl) (eq (plist-get tpl :source) 'bundled))
                    (health-chart-org-templates))))

(ert-deftest health-chart-org-test-stamp-every-template ()
  (let ((context (health-chart-org-context :person "alex" :date "2025-10-01")))
    (should (equal (plist-get context :period) "2024-10-01 – 2025-10-01"))
    (should (equal (plist-get context :year) "2025"))
    (dolist (tpl (health-chart-org-template-list))
      (let ((text (health-chart-org-stamp (plist-get tpl :name) context)))
        (should-not (string-match-p "{{" text))
        (should (string-match-p "^#\\+TITLE: .*alex" text))
        ;; every block in a stamped template explains cleanly
        (with-temp-buffer
          (insert text)
          (goto-char (point-min))
          (while (re-search-forward "^#\\+BEGIN: \\(health-[a-z]+\\)\\(.*\\)$" nil t)
            (let ((plan (health-chart-org-explain (match-string 1)
                                                  (car (read-from-string
                                                        (concat "(" (match-string 2) ")")))
                                                  "/tmp/r.org")))
              (should (eq (plist-get plan :valid) t)))))))))

(ert-deftest health-chart-org-test-user-template-shadows ()
  (let* ((dir (make-temp-file "hc-org-tpl" t))
         (health-chart-org-template-directories (list dir)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "lab-draw.org" dir)
            (insert "#+TITLE: Mine · {{person}}\n{{nope}}\n"))
          (with-temp-file (expand-file-name "extra.org" dir) (insert "#+TITLE: Extra\n"))
          (let ((list (health-chart-org-template-list)))
            (should (eq (plist-get (seq-find (lambda (tpl) (equal (plist-get tpl :name) "lab-draw")) list)
                                   :source)
                        'user))
            (should (member "extra" (mapcar (lambda (tpl) (plist-get tpl :name)) list))))
          (let ((err (should-error (health-chart-org-stamp "lab-draw" (health-chart-org-context
                                                                       :person "alex" :date "2025-01-01"))
                                   :type 'health-chart-template-error)))
            (should (string-match-p "lab-draw.org:2: unknown placeholder {{nope}}" (cadr err))))
          (should-error (health-chart-org-template-find "missing") :type 'health-chart-org-error))
      (delete-directory dir t))))

(ert-deftest health-chart-org-test-new-report-stamps-and-refreshes ()
  (health-chart-org-test-env
    (let ((out (health-chart-org-new-report "genetics-summary" "r/g.org"
                                            :person "alex" :date "2025-10-01")))
      (should (file-exists-p out))
      (let ((text (with-temp-buffer (insert-file-contents out) (buffer-string))))
        (should (string-match-p "^#\\+TITLE: Genetics summary · alex$" text))
        (should (string-match-p "^/Genetics apoe: genetics.el is not loaded" text)))
      (kill-buffer (get-file-buffer out)))))

;; -----------------------------------------------------------------------
;; Images and export, when the tools are installed
;; -----------------------------------------------------------------------

(ert-deftest health-chart-org-test-chart-block-writes-image ()
  (skip-unless (health-chart-gnuplot-available-p))
  (health-chart-org-test-env
    (let* ((doc "#+BEGIN: health-chart :kind timeseries :person \"alex\" :marker \"ldl_c\" :backend gnuplot :caption \"LDL-C\"\n#+END:\n")
           (out (health-chart-org-test-update doc))
           (plan (health-chart-org-chart-explain
                  '(:kind timeseries :person "alex" :marker "ldl_c" :backend gnuplot :caption "LDL-C")
                  (expand-file-name "report.org"))))
      (should (string-match-p "^#\\+CAPTION: LDL-C$" out))
      (should (string-search (format "[[file:%s]]" (plist-get plan :link)) out))
      (should (file-exists-p (plist-get plan :output)))
      (should (equal out (health-chart-org-test-update out))))))

(ert-deftest health-chart-org-test-export-smoke ()
  (skip-unless (or (health-chart-vega-lite-available-p) (health-chart-gnuplot-available-p)))
  (health-chart-org-test-env
    (let* ((org (health-chart-org-new-report "lab-draw" "lab.org" :person "alex"
                                             :date "2025-10-01"))
           (html (expand-file-name "lab.html"))
           (tex (expand-file-name "lab.tex"))
           (org-export-time-stamp-file nil))
      (with-current-buffer (find-file-noselect org)
        (org-export-to-file 'html html)
        (org-export-to-file 'latex tex)
        (should-not (string-match-p "\\.png\\]\\]" (buffer-string)))
        (kill-buffer))
      (let ((h (with-temp-buffer (insert-file-contents html) (buffer-string)))
            (l (with-temp-buffer (insert-file-contents tex) (buffer-string))))
        (should (string-match-p "<img src=\"lab-assets/bullet-alex-[0-9a-f]+\\.svg\"" h))
        (should (string-match-p "<table" h))
        (should (string-match-p "\\\\includegraphics\\[[^]]*\\]{lab-assets/bullet-alex-[0-9a-f]+\\.png}" l))
        (should-not (string-match-p "\\.svg}" l))))))

(provide 'health-chart-org-test)
;;; health-chart-org-test.el ends here

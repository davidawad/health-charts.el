;;; health-chart-batch-test.el --- The JSON command line -*- lexical-binding: t; -*-

;;; Code:

(require 'health-chart-test-helpers)
(require 'health-chart-batch)
(require 'json)

(defun health-chart-batch-test--run (&rest args)
  "Run batch ARGS in-process; return (STATUS . STDOUT)."
  (let (status)
    (let ((out (with-output-to-string
                 (setq status (apply #'health-chart-batch-run args)))))
      (cons status out))))

(defun health-chart-batch-test--json (out)
  "OUT parsed as JSON."
  (json-parse-string out :object-type 'alist :array-type 'list :null-object nil :false-object :false))

(defun health-chart-batch-test--spec-file (spec)
  "Write SPEC (a JSON-able value) to a temp file; return its name."
  (let ((file (make-temp-file "health-chart-spec" nil ".json")))
    (with-temp-file file (insert (json-encode spec)))
    file))

(ert-deftest health-chart-batch-test-example-renders-for-every-kind ()
  (health-chart-test-env
    (dolist (kind (mapcar #'car health-chart-kinds))
      (let* ((example (cdr (health-chart-batch-test--run "example" (symbol-name kind))))
             (spec (health-chart-batch-test--json example))
             (file (health-chart-batch-test--spec-file spec)))
        (unwind-protect
            (let ((result (health-chart-batch-test--run "render" file)))
              (if (and (equal (alist-get 'backend spec) "gnuplot")
                       (not (health-chart-gnuplot-available-p)))
                  ;; template-only kinds need gnuplot; without it the
                  ;; failure must be the typed one
                  (progn (should (= 1 (car result)))
                         (should (string-match-p "\"backend_missing\"" (cdr result))))
                (should (= 0 (car result)))
                (should (> (length (cdr result)) 5))
                (should-not (string-match-p "\"ok\":false" (cdr result)))))
          (delete-file file))))))

(ert-deftest health-chart-batch-test-render-matches-plot ()
  (health-chart-test-env
    (let ((file (health-chart-batch-test--spec-file
                 `((kind . "bullet") (person . "alex") (backend . "text")
                   (data . ,(json-parse-string (health-chart-test-read "biomarker-query.json")
                                             :null-object nil))))))
      (unwind-protect
          (should (equal (cdr (health-chart-batch-test--run "render" file))
                         (concat (substring-no-properties
                                  (health-chart-plot 'bullet (health-chart-test-ms) :person "alex"
                                                     :backend 'text))
                                 "\n")))
        (delete-file file)))))

(ert-deftest health-chart-batch-test-false-props-turn-bands-off ()
  (health-chart-test-env
    (let ((file (health-chart-batch-test--spec-file
                 `((kind . "timeseries") (backend . "text") (ref . :json-false) (optimal . :json-false)
                   (data . ,(json-parse-string (health-chart-test-read "biomarker-latest.json")
                                             :null-object nil))))))
      (unwind-protect
          (let ((out (cdr (health-chart-batch-test--run "render" file))))
            (should-not (string-search "░" out))
            (should-not (string-search "▒" out)))
        (delete-file file)))))

(ert-deftest health-chart-batch-test-explain-validate-and-errors ()
  (health-chart-test-env
    (let ((good (health-chart-batch-test--spec-file
                 `((kind . "table") (data . [((marker . "tsh") (value . 2.0) (date . "2025-01-01"))]))))
          (bad (health-chart-batch-test--spec-file
                `((kind . "table") (data . [((marker . "tsh") (value . "2") (date . "2025-01-01"))]))))
          (nokind (health-chart-batch-test--spec-file '((data . [])))))
      (unwind-protect
          (progn
            (should (equal (health-chart-batch-test--run "validate" good) '(0 . "{\"ok\":true}\n")))
            (let ((plan (health-chart-batch-test--json (cdr (health-chart-batch-test--run "explain" good)))))
              (should (equal (alist-get 'renderer plan) "health-chart-text-table"))
              (should (equal (alist-get 'markers plan) '("tsh"))))
            (let* ((r (health-chart-batch-test--run "validate" bad))
                   (json (health-chart-batch-test--json (cdr r))))
              (should (= 1 (car r)))
              (should (eq (alist-get 'ok json) :false))
              (should (equal (alist-get 'code (alist-get 'error json)) "invalid_data")))
            (should (equal (alist-get 'code (alist-get 'error (health-chart-batch-test--json
                                                                (cdr (health-chart-batch-test--run "render" nokind)))))
                           "bad_request"))
            (should (equal (alist-get 'code (alist-get 'error (health-chart-batch-test--json
                                                                (cdr (health-chart-batch-test--run "frobnicate")))))
                           "bad_request")))
        (mapc #'delete-file (list good bad nokind))))))

(ert-deftest health-chart-batch-test-describe-kinds-doctor ()
  (health-chart-test-env
    (let ((d (health-chart-batch-test--json (cdr (health-chart-batch-test--run "describe")))))
      (should (equal (alist-get 'package d) "health-chart")))
    (should (= (length health-chart-kinds)
               (length (health-chart-batch-test--json (cdr (health-chart-batch-test--run "kinds"))))))
    (should (health-chart-batch-test--json (cdr (health-chart-batch-test--run "doctor"))))))

(ert-deftest health-chart-batch-test-bin-pipe-reads-biomarker-output ()
  ;; the real shell entry point, fed a biomarker/v1 envelope on stdin
  (let ((bin (expand-file-name "../bin/health-chart" health-chart-test-dir))
        (process-environment (cons (concat "EMACS=" (expand-file-name invocation-name invocation-directory))
                                   process-environment)))
    (with-temp-buffer
      (should (= 0 (call-process bin (health-chart-test-fixture "biomarker-query.json") t nil
                                 "pipe" "heatmap" "{\"person\":\"sam\"}")))
      (should (string-match-p "\\`Out of range · sam" (buffer-string))))
    (with-temp-buffer
      (should (= 1 (call-process bin (health-chart-test-fixture "biomarker-query.json") t nil
                                 "pipe" "pie")))
      (should (string-match-p "unknown_kind" (buffer-string))))))

;;; health-chart-batch-test.el ends here

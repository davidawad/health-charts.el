;;; health-chart-source-test.el --- The biomarker data layer -*- lexical-binding: t; -*-

;; Covers both ways in: plain Lisp data, and a source.  The CLI source
;; runs test/fixtures/fake-biomarker, which answers from JSON fixtures,
;; so no biomarker install is needed.

;;; Code:

(require 'health-chart-test-helpers)

(defconst health-chart-source-test--spec-json
  "{\"person\":\"david\",\"marker\":\"ldl_c\",\"value\":112.0,\"unit\":\"mg/dL\",\"date\":\"2025-03-01\",\"ref_low\":0,\"ref_high\":100,\"opt_low\":null,\"opt_high\":70,\"flag\":\"high\"}"
  "The measurement shape biomarker/v1 is assumed to print.")

(defconst health-chart-source-test--canonical
  '(:person "david" :marker "ldl_c" :value 112.0 :unit "mg/dL" :date "2025-03-01"
    :ref-low 0 :ref-high 100 :opt-low nil :opt-high 70 :flag high :category nil
    :label nil)
  "The canonical plist of `health-chart-source-test--spec-json'.")

(defmacro health-chart-source-test--with-fake-cli (&rest body)
  "Run BODY with the CLI source pointed at the fake biomarker."
  (declare (indent 0))
  `(let ((health-chart-source-executable (health-chart-test-fixture "fake-biomarker"))
         (health-chart-source-function #'health-chart-source-cli)
         (health-chart-source-db nil)
         (health-chart-source-extra-args nil)
         (health-chart-default-person nil)
         (process-environment (copy-sequence process-environment)))
     ,@body))

(ert-deftest health-chart-source-test-parses-the-assumed-wire-shape ()
  (should (equal (health-chart-source-parse (concat "[" health-chart-source-test--spec-json "]"))
                 (list health-chart-source-test--canonical)))
  (should (equal (health-chart-source-parse
                  (format "{\"schema\":\"biomarker/v1\",\"measurements\":[%s]}"
                          health-chart-source-test--spec-json))
                 (list health-chart-source-test--canonical))))

(ert-deftest health-chart-source-test-parses-real-biomarker-cli-output ()
  ;; A record exactly as biomarker-cli 0.1 `query --format json' emits it:
  ;; the draw date is `taken_at', and extra members are ignored.
  (let ((m (car (health-chart-source-parse
                 "{\"schema\":\"biomarker/v1\",\"kind\":\"measurements\",\"count\":1,\"data\":[{\"id\":2,\"person\":\"alex\",\"marker\":\"ldl-c\",\"marker_name\":\"LDL Cholesterol\",\"category\":\"lipid\",\"taken_at\":\"2023-02-14\",\"qualifier\":null,\"value\":138.0,\"unit\":\"mg/dL\",\"ref_low\":null,\"ref_high\":100.0,\"opt_low\":null,\"opt_high\":70.0,\"flag\":\"high\",\"tags\":[\"annual\"]}]}"))))
    (should (equal (plist-get m :date) "2023-02-14"))
    (should (equal (plist-get m :marker) "ldl-c"))
    (should (equal (plist-get m :value) 138.0))
    (should (equal (plist-get m :ref-high) 100.0))
    (should (eq (plist-get m :flag) 'high))))

(ert-deftest health-chart-source-test-normalizes-every-lisp-form ()
  (let ((want health-chart-source-test--canonical))
    ;; plist, canonical keys
    (should (equal (health-chart-source-normalize want) want))
    ;; plist, wire keys
    (should (equal (health-chart-source-normalize
                    '(:person "david" :marker "ldl_c" :value 112.0 :unit "mg/dL" :date "2025-03-01"
                      :ref_low 0 :ref_high 100 :opt_high 70 :flag "high"))
                   want))
    ;; alist with symbol keys, as `json-parse-string' gives
    (should (equal (health-chart-source-normalize
                    '((person . "david") (marker . "ldl_c") (value . 112.0) (unit . "mg/dL")
                      (date . "2025-03-01") (ref_low . 0) (ref_high . 100) (opt_low . :null)
                      (opt_high . 70) (flag . "High") (extra . "ignored")))
                   want))
    ;; alist with string keys and symbol marker
    (should (equal (health-chart-source-normalize
                    '(("person" . "david") ("marker" . ldl_c) ("value" . 112.0) ("unit" . "mg/dL")
                      ("date" . "2025-03-01") ("ref-low" . 0) ("ref-high" . 100)
                      ("opt_high" . 70) ("flag" . high)))
                   want))
    ;; hash table, as `json-parse-string' gives by default
    (should (equal (health-chart-source-normalize (json-parse-string health-chart-source-test--spec-json))
                   want))))

(ert-deftest health-chart-source-test-normalize-list-is-idempotent ()
  (let ((parsed (health-chart-source-parse (health-chart-test-read "biomarker-latest.json"))))
    (should (= 9 (length parsed)))
    (should (equal parsed (health-chart-source-normalize-list parsed)))
    (should (equal parsed (health-chart-source-normalize-list (apply #'vector parsed))))))

(ert-deftest health-chart-source-test-envelope-variants ()
  (let ((m (json-parse-string health-chart-source-test--spec-json :object-type 'alist :null-object nil)))
    (dolist (key '(measurements data results items))
      (should (equal (health-chart-source-normalize-list `((schema . "biomarker/v1") (,key ,m)))
                     (list health-chart-source-test--canonical))))
    ;; a later minor revision is accepted, another major is not
    (should (health-chart-source-normalize-list `((schema . "biomarker/v1.2") (measurements ,m))))
    (let ((err (should-error (health-chart-source-normalize-list `((schema . "biomarker/v2") (measurements ,m)))
                             :type 'health-chart-source-error)))
      (should (equal (plist-get (cddr err) :code) "schema_mismatch")))
    (let ((err (should-error (health-chart-source-parse
                              "{\"schema\":\"biomarker/v1\",\"error\":{\"message\":\"no such person\"}}")
                             :type 'health-chart-source-error)))
      (should (equal (plist-get (cddr err) :code) "source_reported_error"))
      (should (string-match-p "no such person" (cadr err))))))

(ert-deftest health-chart-source-test-bad-json ()
  (let ((err (should-error (health-chart-source-parse "Error: oops") :type 'health-chart-source-error)))
    (should (equal (plist-get (cddr err) :code) "bad_json"))))

(ert-deftest health-chart-source-test-to-json-round-trips ()
  (let ((m health-chart-source-test--canonical))
    (should (equal (health-chart-source-normalize (health-chart-source-to-json m)) m))
    (should (equal (health-chart-source-parse (json-encode (vector (health-chart-source-to-json m))))
                   (list m)))))

(ert-deftest health-chart-source-test-cli-args ()
  (let ((health-chart-source-db nil) (health-chart-source-extra-args nil))
    (should (equal (health-chart-source-cli-args 'latest)
                   '("latest" "--format" "json")))
    (should (equal (health-chart-source-cli-args 'trend :person "alex" :marker "ldl_c" :since "2024-01-01")
                   '("query" "--person" "alex" "--marker" "ldl_c" "--from" "2024-01-01"
                     "--format" "json"))))
  (let ((health-chart-source-db "/tmp/bio.db") (health-chart-source-extra-args '("--quiet")))
    (should (equal (health-chart-source-cli-args 'flag :person "sam")
                   '("--db" "/tmp/bio.db" "flag" "--person" "sam" "--quiet" "--format" "json")))))

(ert-deftest health-chart-source-test-cli-runs-and-parses ()
  (health-chart-source-test--with-fake-cli
    (let ((log (make-temp-file "fake-biomarker-log")))
      (unwind-protect
          (progn
            (setenv "FAKE_BIOMARKER_LOG" log)
            (let ((latest (health-chart-source-latest :person "alex"))
                  (all (health-chart-source-query :person nil)))
              (should (= 9 (length latest)))
              (should (equal (plist-get (car latest) :marker) "ldl_c"))
              (should (= 108 (length all)))
              (should (equal (health-chart-persons all) '("alex" "sam"))))
            (should (equal (with-temp-buffer (insert-file-contents log) (buffer-string))
                           "latest --person alex --format json\nquery --format json\n")))
        (delete-file log)))))

(ert-deftest health-chart-source-test-default-person ()
  (health-chart-source-test--with-fake-cli
    (let ((log (make-temp-file "fake-biomarker-log"))
          (health-chart-default-person "sam"))
      (unwind-protect
          (progn
            (setenv "FAKE_BIOMARKER_LOG" log)
            (health-chart-source-flag)
            (health-chart-source-flag :person nil)
            (should (equal (with-temp-buffer (insert-file-contents log) (buffer-string))
                           "flag --person sam --format json\nflag --format json\n")))
        (delete-file log)))))

(ert-deftest health-chart-source-test-cli-failures-are-typed ()
  (health-chart-source-test--with-fake-cli
    (setenv "FAKE_BIOMARKER_FAIL" "1")
    (let ((err (should-error (health-chart-source-query) :type 'health-chart-source-error)))
      (should (equal (plist-get (cddr err) :code) "source_failed"))
      (should (equal (plist-get (cddr err) :exit) 2))
      (should (string-match-p "database is locked" (cadr err)))))
  (let ((health-chart-source-function #'health-chart-source-cli)
        (health-chart-source-executable "no-such-biomarker-binary"))
    (let ((err (should-error (health-chart-source-query) :type 'health-chart-source-error)))
      (should (equal (plist-get (cddr err) :code) "source_missing"))
      (should (string-match-p "health-chart-source-executable" (cadr err)))))
  (should-error (health-chart-source-fetch 'sing) :type 'health-chart-source-error))

(ert-deftest health-chart-source-test-static-source ()
  (health-chart-test-env
    (should (= 54 (length (health-chart-source-query :person "alex"))))
    (should (= 18 (length (health-chart-source-latest :person nil))))
    (let ((trend (health-chart-source-trend :person "sam" :marker "ldl_c")))
      (should (equal (mapcar (lambda (m) (plist-get m :date)) trend) health-chart--example-dates)))
    (let ((flags (health-chart-source-flag :person "alex")))
      (should flags)
      (should (cl-every #'health-chart-out-of-range-p flags)))
    ;; the last draw: nine markers for each of two people
    (should (= 18 (length (health-chart-source-query :person nil :since "2025-06-01"))))))

(ert-deftest health-chart-source-test-custom-source-function ()
  (let* ((calls nil)
         (health-chart-default-person nil)
         (health-chart-source-function
          (lambda (command &rest args)
            (push (cons command args) calls)
            (list '((marker . "tsh") (value . 2.0) (date . "2025-01-01"))))))
    (should (equal (plist-get (car (health-chart-source-trend :marker "tsh")) :value) 2.0))
    (should (equal calls '((trend :marker "tsh" :person nil))))))

(ert-deftest health-chart-source-test-doctor ()
  (let ((health-chart-source-function #'health-chart-source-cli)
        (health-chart-source-executable "no-such-biomarker-binary")
        (health-chart-source-db nil))
    (let ((rows (health-chart-source-doctor-checks)))
      (should (eq (plist-get (car rows) :status) 'skip))
      (should (eq (plist-get (cadr rows) :status) 'pass))))
  (let ((health-chart-source-function #'health-chart-source-static)
        (health-chart-source-db "/nonexistent/bio.db"))
    (let ((rows (health-chart-source-doctor-checks)))
      (should (eq (plist-get (car rows) :status) 'pass))
      (should (eq (plist-get (cadr rows) :status) 'fail)))))

;;; health-chart-source-test.el ends here

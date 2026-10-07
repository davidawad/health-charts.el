;;; health-chart-api-test.el --- the public API and the shell door -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'health-chart)
(require 'health-chart-cli)
(require 'health-chart-test-support)

(ert-deftest health-chart-api-lists-templates-with-groups-and-docs ()
  (let ((rows (health-chart-list-templates)))
    (should (cl-find "vitals-trend" rows :key #'car :test #'equal))
    (dolist (row rows)
      (should (stringp (car row)))
      (should (stringp (plist-get (cdr row) :doc)))
      (should (stringp (plist-get (cdr row) :group))))
    ;; sorted by group, then name
    (should (equal rows (sort (copy-sequence rows)
                              (lambda (a b)
                                (let ((ga (plist-get (cdr a) :group)) (gb (plist-get (cdr b) :group)))
                                  (if (equal ga gb) (string< (car a) (car b)) (string< ga gb)))))))))

(ert-deftest health-chart-api-describes-a-template ()
  (let ((d (health-chart-describe-template "vitals-trend")))
    (should (equal (plist-get d :name) "vitals-trend"))
    (should (plist-get (plist-get d :slots) :low))
    (should (equal (plist-get (plist-get (plist-get d :tables) :data) :order) "time"))
    (should (plist-get d :example))
    (should (equal (append (plist-get d :text-size) nil) '(100 26)))
    ;; the namespaced name works too
    (should (equal (plist-get (health-chart-describe-template "health/vitals-trend") :name)
                   "vitals-trend"))))

(ert-deftest health-chart-api-unknown-template-signals-with-the-catalog ()
  (let ((err (should-error (health-chart-render "no-such-chart" nil)
                           :type 'health-chart-unknown-template)))
    (should (equal (plist-get (health-chart-error-data err) :code) "unknown_template"))
    (should (string-match-p "vitals-trend" (plist-get (health-chart-error-data err) :message)))))

(ert-deftest health-chart-api-check-returns-t-or-a-plist ()
  (let ((good (health-chart-example "vitals-trend")))
    (should (eq t (health-chart-check "vitals-trend" good)))
    (let ((bad (health-chart-check "vitals-trend"
                                   (plist-put (copy-sequence good) :data
                                              [(:time "2026-03-01" :value "x")]))))
      (should (equal (plist-get bad :code) "not_a_number"))
      (should (equal (plist-get bad :path) "data[0].value"))
      (should (equal (plist-get bad :index) 0))
      (should (equal (plist-get bad :field) "value"))
      (should (stringp (plist-get bad :message))))))

(ert-deftest health-chart-api-validation-names-slots ()
  (let ((good (health-chart-example "vitals-trend")))
    ;; a slot the template does not have
    (health-chart-test-should-code
     "slot_unknown" "nonsense"
     (lambda () (health-chart-validate "vitals-trend" (plist-put (copy-sequence good) :nonsense 1))))
    ;; a required slot left out
    (health-chart-test-should-code
     "missing_slot" "low"
     (lambda () (health-chart-validate
                 "vitals-trend" (cl-loop for (k v) on good by #'cddr unless (eq k :low) append (list k v)))))
    ;; a slot of the wrong type
    (health-chart-test-should-code
     "slot_type" "high"
     (lambda () (health-chart-validate "vitals-trend" (plist-put (copy-sequence good) :high "100"))))
    ;; not an object
    (health-chart-test-should-code
     "not_an_object" nil
     (lambda () (health-chart-validate "vitals-trend" [1 2])))
    ;; range inverted
    (health-chart-test-should-code
     "range_inverted" "high"
     (lambda () (health-chart-validate "vitals-trend"
                                       (plist-put (plist-put (copy-sequence good) :low 100) :high 60))))))

(ert-deftest health-chart-api-times-are-checked-strictly ()
  (dolist (bad '("2026-02-30" "2026-03-01T25:00" "03/01/2026" "2026-3-1" "yesterday" ""))
    (let ((data (plist-put (copy-sequence (health-chart-example "vitals-trend")) :data
                           (vector (list :time bad :value 70)))))
      (health-chart-test-should-code "not_a_time" "data[0].time"
                                     (lambda () (health-chart-validate "vitals-trend" data)))))
  (dolist (good '("2026-03-01" "2026-03-01T08:30" "2026-03-01T08:30:15" "2026-03-01 08:30"
                  "2026-03-01T08:30:15Z" "2026-03-01T08:30:15+02:00" "2024-02-29"))
    (should (eq t (health-chart-validate
                   "vitals-trend"
                   (plist-put (copy-sequence (health-chart-example "vitals-trend")) :data
                              (vector (list :time good :value 70))))))))

(ert-deftest health-chart-api-render-honours-backend-size-and-title ()
  (let* ((b (health-chart-example "vitals-trend"))
         (text (health-chart-render "vitals-trend" b :backend 'text :width 60 :height 14
                                    :title "Override"))
         (lines (split-string (substring-no-properties text) "\n")))
    (should (string-match-p "Override" text))
    (should (<= (length lines) 16))
    (should (<= (apply #'max (mapcar #'string-width lines)) 62)))
  (let ((svg (health-chart-render "vitals-trend" (health-chart-example "vitals-trend")
                                  :backend 'svg :width 640 :height 300 :font "Courier")))
    (should (string-match-p "viewBox=\"0 0 640 300\"\\|width=\"640\"" svg))
    (should (string-match-p "Courier" svg)))
  (should-error (health-chart-render "vitals-trend" (health-chart-example "vitals-trend")
                                     :backend 'png)
                :type 'health-chart-backend-error))

(ert-deftest health-chart-api-render-validates-first ()
  (health-chart-test-should-code
   "not_a_number" "data[0].value"
   (lambda () (health-chart-render "vitals-trend"
                                   (plist-put (copy-sequence (health-chart-example "vitals-trend"))
                                              :data [(:time "2026-03-01" :value nil)])
                                   :backend 'text))))

(ert-deftest health-chart-api-reads-json-and-writes-files ()
  (let* ((json (json-serialize (list :low 60 :high 100
                                     :data (vector (list :time "2026-03-01" :value 70)
                                                   (list :time "2026-03-02" :value 120)))))
         (bindings (health-chart-read-bindings json))
         (file (make-temp-file "health-chart" nil ".svg")))
    (unwind-protect
        (progn
          (should (eq t (health-chart-validate "vitals-trend" bindings)))
          (health-chart-write "vitals-trend" bindings file)
          (should (string-prefix-p "<svg" (with-temp-buffer (insert-file-contents file)
                                                            (string-trim-left (buffer-string)))))
          (let ((txt (concat file ".txt")))
            (health-chart-write "vitals-trend" bindings txt)
            (should (> (file-attribute-size (file-attributes txt)) 200))
            (delete-file txt)))
      (delete-file file))))

(ert-deftest health-chart-api-opens-a-live-view ()
  (let ((view (health-chart-open "vitals-trend" (health-chart-example "vitals-trend")
                                 :backend 'text :id "health-test")))
    (unwind-protect
        (progn
          (should (equal (eas-view-id view) "health-test"))
          (should (buffer-live-p (get-buffer "*eas health-test*"))))
      (when (get-buffer "*eas health-test*") (kill-buffer "*eas health-test*")))))

(ert-deftest health-chart-cli-validates-and-lists ()
  (let* ((ok (health-chart-cli-run '("templates"))))
    (should (= (car ok) 0))
    (should (string-match-p "vitals-trend" (cdr ok))))
  (let* ((file (make-temp-file "health-chart" nil ".json")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert (eas-json-encode (plist-put (copy-sequence (health-chart-example "vitals-trend"))
                                                :data [(:time "2026-99-99" :value 1)]))))
          (let ((bad (health-chart-cli-run (list "validate" "vitals-trend" "--data" file))))
            (should (= (car bad) 1))
            (should (string-match-p "\"code\": \"not_a_time\"" (cdr bad)))
            (should (string-match-p "\"path\": \"data\\[0\\].time\"" (cdr bad)))))
      (delete-file file)))
  (let ((usage (health-chart-cli-run '("validate"))))
    (should (= (car usage) 1)))
  ;; any other verb is eas's, with the templates loaded
  (should (= (car (health-chart-cli-run '("describe" "templates"))) 0)))

(provide 'health-chart-api-test)
;;; health-chart-api-test.el ends here

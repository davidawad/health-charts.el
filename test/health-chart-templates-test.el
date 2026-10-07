;;; health-chart-templates-test.el --- every template: example, goldens, validation -*- lexical-binding: t; -*-

;;; Commentary:

;; One group of tests per template, generated from the template catalog:
;; its example validates and renders to text and SVG against goldens, and
;; every field its `health' block declares fails with the right code and
;; JSON path when broken.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'health-chart)
(require 'health-chart-test-support)

(defun health-chart-test--text (name)
  "Template NAME's example drawn as plain text."
  (substring-no-properties
   (health-chart-render name (health-chart-example name) :backend 'text)))

(defun health-chart-test--svg (name)
  "Template NAME's example drawn as SVG."
  (health-chart-render name (health-chart-example name) :backend 'svg))

(defun health-chart-test--rows (bindings table)
  "The rows of TABLE (a keyword) in BINDINGS, as a list."
  (append (plist-get bindings table) nil))

(defun health-chart-test--with-row (bindings table index row)
  "A copy of BINDINGS whose TABLE row INDEX is ROW."
  (let ((rows (vconcat (health-chart-test--rows bindings table))))
    (aset rows index row)
    (plist-put (copy-sequence bindings) table rows)))

(defun health-chart-test--without (row key)
  "ROW (a plist) without KEY."
  (cl-loop for (k v) on row by #'cddr unless (eq k key) append (list k v)))

(defun health-chart-test--bad-value (type)
  "A value that breaks field TYPE, with the code it must fail as: (VALUE . CODE)."
  (let ((type (string-remove-prefix "?" type)))
    (cond ((member type '("number")) '("x" . "not_a_number"))
          ((equal type "nonneg") '(-1 . "negative_value"))
          ((member type '("percent" "fraction")) '(1000 . "out_of_range"))
          ((string-prefix-p "range:" type) '(1000000 . "out_of_range"))
          ((equal type "int") '(1.5 . "not_an_integer"))
          ((equal type "nonnegint") '(-3 . "negative_value"))
          ((equal type "string") '(5 . "not_a_string"))
          ((equal type "time") '("2026-13-45" . "not_a_time"))
          ((equal type "date") '("March 1" . "not_a_date"))
          ((equal type "bool") '("yes" . "not_a_bool"))
          ((string-prefix-p "enum:" type) '("no-such-choice" . "not_in_enum")))))

(defun health-chart-test--check-schema (name)
  "Break every field NAME's `health' block declares and expect its code and path."
  (let* ((example (health-chart-example name))
         (described (health-chart-describe-template name))
         (tables (plist-get described :tables)))
    (should tables)
    (cl-loop
     for (table spec) on tables by #'cddr
     for slot = (substring (symbol-name table) 1)
     for rows = (health-chart-test--rows example table)
     do
     (should rows)
     ;; a missing slot, a non-list, an empty list, a non-object row
     (unless (plist-get spec :optional)
       (health-chart-test-should-code
        "missing_slot" slot
        (lambda () (health-chart-validate name (health-chart-test--without example table)))))
     (health-chart-test-should-code
      "not_a_list" slot
      (lambda () (health-chart-validate name (plist-put (copy-sequence example) table "nope"))))
     (when (>= (or (plist-get spec :min_rows) 1) 1)
       (health-chart-test-should-code
        "too_few_rows" slot
        (lambda () (health-chart-validate name (plist-put (copy-sequence example) table [])))))
     (health-chart-test-should-code
      "not_a_row" (format "%s[0]" slot)
      (lambda () (health-chart-validate name (health-chart-test--with-row example table 0 "row"))))
     ;; every field
     (cl-loop
      for (key type) on (plist-get spec :fields) by #'cddr
      for field = (substring (symbol-name key) 1)
      for row = (car rows)
      for path = (format "%s[0].%s" slot field)
      do
      (unless (string-prefix-p "?" type)
        (health-chart-test-should-code
         "missing_field" path
         (lambda () (health-chart-validate
                     name (health-chart-test--with-row
                           example table 0 (health-chart-test--without row key))))))
      (when-let* ((bad (health-chart-test--bad-value type)))
        (let ((data (health-chart-test-should-code
                     (cdr bad) path
                     (lambda () (health-chart-validate
                                 name (health-chart-test--with-row
                                       example table 0 (plist-put (copy-sequence row) key (car bad))))))))
          (should (equal (plist-get data :index) 0))
          (should (equal (plist-get data :field) field)))))
     ;; chronological order
     (when-let* ((order (plist-get spec :order)))
       (let* ((rev (vconcat (reverse rows)))
              (times (mapcar (lambda (r) (plist-get r (intern (concat ":" order)))) rows)))
         (when (and (> (length rows) 1) (not (equal (car times) (car (last times)))))
           (health-chart-test-should-code
            "time_not_ascending" nil
            (lambda () (health-chart-validate name (plist-put (copy-sequence example) table rev))))))))
    ;; typed scalar slots
    (cl-loop for (key type) on (plist-get described :slots-typed) by #'cddr
             for bad = (health-chart-test--bad-value type)
             do (health-chart-test-should-code
                 (cdr bad) (substring (symbol-name key) 1)
                 (lambda () (health-chart-validate name (plist-put (copy-sequence example) key (car bad))))))
    ;; row rules: swap the pair in row 0
    (cl-loop for (table spec) on tables by #'cddr
             do (dolist (rule (append (plist-get spec :rows) nil))
                  (let* ((a (intern (concat ":" (aref (plist-get rule :le) 0))))
                         (b (intern (concat ":" (aref (plist-get rule :le) 1))))
                         (row (car (health-chart-test--rows example table))))
                    (unless (equal (plist-get row a) (plist-get row b))
                      (health-chart-test-should-code
                       (plist-get rule :code) nil
                       (lambda ()
                         (health-chart-validate
                          name (health-chart-test--with-row
                                example table 0
                                (plist-put (plist-put (copy-sequence row) a (plist-get row b))
                                           b (plist-get row a))))))))))
    ;; slot rules: swap the pair
    (dolist (rule (append (plist-get described :rules) nil))
      (when-let* ((pair (plist-get rule :le)))
        (let* ((a (intern (concat ":" (aref pair 0)))) (b (intern (concat ":" (aref pair 1))))
               (swapped (plist-put (plist-put (copy-sequence example) a (plist-get example b))
                                   b (plist-get example a))))
          (unless (equal (plist-get example a) (plist-get example b))
            (health-chart-test-should-code (plist-get rule :code) (aref pair 1)
                                           (lambda () (health-chart-validate name swapped)))))))))

(dolist (name (health-chart-template-names))
  (let ((sym (intern (format "health-chart-template-%s" name))))
    (eval
     `(ert-deftest ,(intern (format "%s-example-validates" sym)) ()
        (should (eq t (health-chart-validate ,name (health-chart-example ,name))))
        (should (eq t (health-chart-check ,name (health-chart-example ,name))))
        (should (plist-get (health-chart-describe-template ,name) :doc))
        (should (plist-get (health-chart-describe-template ,name) :group)))
     t)
    (eval
     `(ert-deftest ,(intern (format "%s-text-golden" sym)) ()
        (let ((text (health-chart-test--text ,name)))
          (should (> (length text) 200))
          (should-not (string-match-p "UNSUPPORTED" text))
          (health-chart-test-golden "text" ,(concat name ".txt") text)))
     t)
    (eval
     `(ert-deftest ,(intern (format "%s-svg-golden" sym)) ()
        (let ((svg (health-chart-test--svg ,name)))
          (should (string-prefix-p "<svg" (string-trim-left svg)))
          (health-chart-test-golden "svg" ,(concat name ".svg") svg)))
     t)
    (eval
     `(ert-deftest ,(intern (format "%s-validation-errors" sym)) ()
        (health-chart-test--check-schema ,name))
     t)))

(ert-deftest health-chart-every-template-loaded-cleanly ()
  (should-not eas-template-load-errors)
  (should (>= (length (health-chart-template-names)) 20)))

(ert-deftest health-chart-every-template-has-a-text-and-an-svg-golden ()
  (dolist (name (health-chart-template-names))
    (should (file-exists-p (expand-file-name (concat "test/golden/text/" name ".txt")
                                             health-chart-test-root)))
    (should (file-exists-p (expand-file-name (concat "test/golden/svg/" name ".svg")
                                             health-chart-test-root)))))

(provide 'health-chart-templates-test)
;;; health-chart-templates-test.el ends here

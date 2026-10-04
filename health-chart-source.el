;;; health-chart-source.el --- Swappable biomarker data layer for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The only file that knows the biomarker-cli wire format.  Everything
;; else consumes canonical measurement plists (see health-chart-core.el).
;;
;; Two ways in:
;;
;;   plain Lisp  `health-chart-source-normalize' / `-normalize-list' turn
;;               plists (:ref-low or :ref_low), alists (symbol or string
;;               keys), hash tables, or a biomarker/v1 envelope into
;;               canonical plists.  Charts accept any of these directly.
;;
;;   a source    `health-chart-source-fetch' COMMAND &rest ARGS calls
;;               `health-chart-source-function'.  The default,
;;               `health-chart-source-cli', runs
;;
;;                 biomarker [--db DB] COMMAND [--person P] [--marker M]
;;                           [--since D] [--until D] --format json
;;
;;               and parses its JSON.  `health-chart-source-static' serves
;;               `health-chart-source-static-data' instead (no process),
;;               and any function of (COMMAND &rest ARGS) can replace both.
;;
;; COMMAND is one of query, trend, latest, flag.  ARGS is a plist of
;; :person :marker :since :until.
;;
;; Assumed wire format (biomarker/v1).  A command prints either a JSON
;; array of measurements or an envelope object
;;
;;   {"schema": "biomarker/v1", "measurements": [...]}
;;
;; ("data", "results" or "items" are accepted for the list as well), and
;; a measurement is
;;
;;   {"person":"alex","marker":"ldl_c","value":112.0,"unit":"mg/dL",
;;    "date":"2025-03-01","ref_low":0,"ref_high":100,"opt_low":null,
;;    "opt_high":70,"flag":"high"}
;;
;; An envelope with an "error" member, or a schema other than
;; `health-chart-source-schema', signals `health-chart-source-error'.
;; Adjust `health-chart-source-fields', `health-chart-source-list-keys'
;; and `health-chart-source-cli-args' if the CLI settles on other names.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'health-chart-core)

(define-error 'health-chart-source-error
  "health-chart: biomarker source failed" 'health-chart-error)

(defcustom health-chart-source-executable "biomarker"
  "The biomarker-cli executable.
A name looked up on variable `exec-path', or an absolute path."
  :type 'string
  :group 'health-charts)

(defcustom health-chart-source-db nil
  "Database file passed to biomarker as --db, or nil for its own default."
  :type '(choice (const :tag "biomarker's default" nil) file)
  :group 'health-charts)

(defcustom health-chart-default-person nil
  "Person fetched when a request names none, or nil for every person."
  :type '(choice (const :tag "Everyone" nil) string)
  :group 'health-charts)

(defcustom health-chart-source-extra-args nil
  "Extra arguments appended to every biomarker invocation."
  :type '(repeat string)
  :group 'health-charts)

(defcustom health-chart-source-schema "biomarker/v1"
  "Schema an envelope must declare.  A later minor revision is accepted."
  :type 'string
  :group 'health-charts)

(defcustom health-chart-source-function #'health-chart-source-cli
  "Function fetching measurements: (COMMAND &rest ARGS) -> list.
COMMAND is a symbol (query, trend, latest or flag); ARGS a plist with
:person :marker :since :until.  The result may be canonical plists, raw
alists or a biomarker/v1 envelope; `health-chart-source-fetch'
normalizes it.  `health-chart-source-cli' runs the biomarker CLI,
`health-chart-source-static' serves `health-chart-source-static-data'."
  :type '(choice (function-item health-chart-source-cli)
                 (function-item health-chart-source-static)
                 function)
  :group 'health-charts)

(defvar health-chart-source-static-data nil
  "Measurements `health-chart-source-static' serves, in any accepted form.")

(defconst health-chart-source-commands '(query trend latest flag)
  "The biomarker commands a source answers.")

;; -----------------------------------------------------------------------
;; Wire format
;; -----------------------------------------------------------------------

(defconst health-chart-source-fields
  '((person . :person) (marker . :marker) (value . :value) (unit . :unit)
    (date . :date) (ref_low . :ref-low) (ref_high . :ref-high)
    (opt_low . :opt-low) (opt_high . :opt-high) (flag . :flag)
    (category . :category) (marker_name . :label))
  "JSON member name -> canonical plist key.  Unknown members are dropped.")

(defconst health-chart-source-field-aliases
  '((taken_at . :date))
  "Other JSON member names for a canonical key, as biomarker-cli emits them.")

(defconst health-chart-source-list-keys '(measurements data results items)
  "Envelope members that may hold the measurement list, in order.")

(defun health-chart-source--key (key)
  "Canonical keyword for KEY: a JSON name, string, or keyword in either spelling."
  (let* ((name (cond ((keywordp key) (substring (symbol-name key) 1))
                     ((symbolp key) (symbol-name key))
                     (t (format "%s" key))))
         (wire (intern (replace-regexp-in-string "-" "_" name))))
    (or (alist-get wire health-chart-source-fields)
        (alist-get wire health-chart-source-field-aliases))))

(defun health-chart-source--value (key v)
  "Canonical form of value V for canonical KEY."
  (cond
   ((memq v '(:null :json-null :json-false nil)) nil)
   ((and (eq key :date) (health-chart-date-p v))
    ;; charts work in calendar days; a time of day would split one draw day
    (substring v 0 10))
   ((eq key :flag)
    (let ((s (downcase (string-trim (format "%s" v)))))
      (unless (string-empty-p s) (intern s))))
   ((memq key '(:marker :person :category :unit :label))
    (if (symbolp v) (symbol-name v) v))
   (t v)))

(defun health-chart-source--pairs (m)
  "Measurement M (plist, alist or hash table) as a list of (KEY . VALUE)."
  (cond
   ((hash-table-p m)
    (let (pairs) (maphash (lambda (k v) (push (cons k v) pairs)) m) (nreverse pairs)))
   ((and (consp m) (keywordp (car m)))
    (cl-loop for (k v) on m by #'cddr collect (cons k v)))
   ((and (consp m) (consp (car m))) m)
   (t (signal 'health-chart-error
              (list (format "a measurement must be a plist, alist or hash table, got %S" m)
                    :code "invalid_data")))))

(defun health-chart-source-normalize (m)
  "Measurement M in any accepted form as a canonical plist.
Keys appear in `health-chart-source-fields' order; absent ones are nil.
When a key occurs twice the first occurrence wins, as in a plist."
  (let (found)
    (dolist (pair (health-chart-source--pairs m))
      (when-let* ((key (health-chart-source--key (car pair))))
        (unless (assq key found)
          (push (cons key (health-chart-source--value key (cdr pair))) found))))
    (cl-loop for (_ . key) in health-chart-source-fields
             append (list key (cdr (assq key found))))))

(defun health-chart-source--envelope-p (data)
  "Non-nil when DATA is a JSON object (alist or hash) rather than a list."
  (or (hash-table-p data)
      (and (consp data) (consp (car data)) (symbolp (caar data))
           (or (assq 'schema data) (assq 'error data)
               (cl-some (lambda (k) (assq k data)) health-chart-source-list-keys)))))

(defun health-chart-source--get (object key)
  "Member KEY (a symbol) of JSON OBJECT, an alist or hash table."
  (if (hash-table-p object)
      (gethash (symbol-name key) object)
    (alist-get key object)))

(defun health-chart-source--schema-ok-p (schema)
  "Non-nil when SCHEMA is compatible with `health-chart-source-schema'."
  (or (equal schema health-chart-source-schema)
      (string-prefix-p (concat health-chart-source-schema ".") schema)))

(defun health-chart-source-unwrap (data)
  "The measurement list inside DATA, a biomarker/v1 envelope or a list."
  (if (not (health-chart-source--envelope-p data))
      (append data nil)
    (when-let* ((err (health-chart-source--get data 'error)))
      (signal 'health-chart-source-error
              (list (format "biomarker reported: %s"
                            (if (stringp err) err
                              (or (health-chart-source--get err 'message) err)))
                    :code "source_reported_error")))
    (let ((schema (health-chart-source--get data 'schema)))
      (when (and schema (not (health-chart-source--schema-ok-p schema)))
        (signal 'health-chart-source-error
                (list (format "schema %s is not %s; upgrade health-chart or set `health-chart-source-schema'"
                              schema health-chart-source-schema)
                      :code "schema_mismatch" :schema schema))))
    (append (cl-some (lambda (k) (health-chart-source--get data k))
                     health-chart-source-list-keys)
            nil)))

(defun health-chart-source-normalize-list (data)
  "DATA (envelope, list or vector of measurements) as canonical plists.
Canonical plists pass through unchanged, so this is idempotent."
  (mapcar #'health-chart-source-normalize (health-chart-source-unwrap data)))

(defun health-chart-source-to-json (m)
  "Canonical measurement M as a wire-format alist (JSON member names).
Absent members are omitted; `json-encode' turns the result into a
biomarker/v1 measurement object."
  (cl-loop for (wire . key) in health-chart-source-fields
           for v = (plist-get m key)
           when v collect (cons wire (if (and (eq key :flag) (symbolp v)) (symbol-name v) v))))

(defun health-chart-source-parse (json)
  "Canonical measurements from the JSON string a biomarker command printed."
  (health-chart-source-normalize-list
   (condition-case err
       (json-parse-string json :object-type 'alist :array-type 'list
                          :null-object nil :false-object nil)
     (json-parse-error
      (signal 'health-chart-source-error
              (list (format "biomarker printed invalid JSON (%s): %s"
                            (error-message-string err)
                            (truncate-string-to-width (string-trim json) 120 nil nil "…"))
                    :code "bad_json"))))))

;; -----------------------------------------------------------------------
;; Sources
;; -----------------------------------------------------------------------

(defun health-chart-source--check-command (command)
  "Signal unless COMMAND is a known source command."
  (unless (memq command health-chart-source-commands)
    (signal 'health-chart-source-error
            (list (format "unknown source command %S; use one of %s" command
                          (mapconcat #'symbol-name health-chart-source-commands ", "))
                  :code "bad_request"))))

(defun health-chart-source-cli-args (command &rest args)
  "The argument list biomarker gets for COMMAND with ARGS (a plist)."
  (append (when health-chart-source-db
            (list "--db" (expand-file-name health-chart-source-db)))
          ;; biomarker's own `trend' answers summary statistics, not the
          ;; series; the series is what `query' returns.
          (list (symbol-name (if (eq command 'trend) 'query command)))
          (cl-loop for (key flag) in '((:person "--person") (:marker "--marker")
                                       (:since "--from") (:until "--to"))
                   for v = (plist-get args key)
                   when v append (list flag (format "%s" v)))
          health-chart-source-extra-args
          (list "--format" "json")))

(defun health-chart-source-cli (command &rest args)
  "Run biomarker COMMAND with ARGS; return its parsed measurements."
  (health-chart-source--check-command command)
  (let ((exe (or (executable-find health-chart-source-executable)
                 (signal 'health-chart-source-error
                         (list (format "cannot find %s; install biomarker-cli or set `health-chart-source-executable'"
                                       health-chart-source-executable)
                               :code "source_missing"))))
        (cli-args (apply #'health-chart-source-cli-args command args))
        (stderr (make-temp-file "health-chart-stderr")))
    (unwind-protect
        (with-temp-buffer
          (let ((status (apply #'call-process exe nil (list t stderr) nil cli-args)))
            (unless (eql status 0)
              (signal 'health-chart-source-error
                      (list (format "%s %s exited %s: %s" exe (string-join cli-args " ") status
                                    (string-trim (with-temp-buffer
                                                   (insert-file-contents stderr)
                                                   (buffer-string))))
                            :code "source_failed" :exit status)))
            (health-chart-source-parse (buffer-string))))
      (delete-file stderr))))

(defun health-chart-source-static (command &rest args)
  "Answer COMMAND with ARGS from `health-chart-source-static-data'.
query and trend return the matches oldest first; latest the newest draw
per marker; flag every match outside its reference range."
  (health-chart-source--check-command command)
  (let ((ms (health-chart-sort-by-date
             (health-chart-filter (health-chart-source-normalize-list
                                   health-chart-source-static-data)
                                  :person (plist-get args :person)
                                  :marker (plist-get args :marker)
                                  :since (plist-get args :since)
                                  :until (plist-get args :until)))))
    (pcase command
      ('latest (apply #'append
                      (mapcar (lambda (p) (health-chart-latest (health-chart-filter ms :person p)))
                              (or (health-chart-persons ms) '(nil)))))
      ('flag (seq-filter #'health-chart-out-of-range-p ms))
      (_ ms))))

(defun health-chart-source-fetch (command &rest args)
  "Measurements for source COMMAND with ARGS, canonical and oldest first.
ARGS: :person (default `health-chart-default-person'; pass :person nil
explicitly for everyone) :marker :since :until.  Calls
`health-chart-source-function'."
  (unless (plist-member args :person)
    (setq args (plist-put (copy-sequence args) :person health-chart-default-person)))
  (health-chart-source-normalize-list
   (apply health-chart-source-function command args)))

(defun health-chart-source-query (&rest args)
  "Every measurement matching ARGS (see `health-chart-source-fetch')."
  (apply #'health-chart-source-fetch 'query args))

(defun health-chart-source-trend (&rest args)
  "One marker's history matching ARGS (see `health-chart-source-fetch')."
  (apply #'health-chart-source-fetch 'trend args))

(defun health-chart-source-latest (&rest args)
  "The newest draw per marker matching ARGS (see `health-chart-source-fetch')."
  (apply #'health-chart-source-fetch 'latest args))

(defun health-chart-source-flag (&rest args)
  "Out-of-range measurements matching ARGS (see `health-chart-source-fetch')."
  (apply #'health-chart-source-fetch 'flag args))

(defun health-chart-source-doctor-checks ()
  "Doctor rows for the data source.  Look up the executable; run nothing."
  (let ((cli (eq health-chart-source-function #'health-chart-source-cli))
        (exe (executable-find health-chart-source-executable)))
    (list
     (cond
      ((not cli)
       (list :name "source" :status 'pass
             :detail (format "custom source %s" health-chart-source-function)))
      (exe (list :name "source" :status 'pass :detail (format "biomarker at %s" exe)))
      (t (list :name "source" :status 'skip
               :detail (format "%s not found; charts still work from Lisp data"
                               health-chart-source-executable)
               :remediation "install biomarker-cli or set `health-chart-source-executable'")))
     (if (and health-chart-source-db
              (not (file-exists-p (expand-file-name health-chart-source-db))))
         (list :name "source-db" :status 'fail
               :detail (format "%s does not exist" health-chart-source-db)
               :remediation "fix `health-chart-source-db' or set it to nil")
       (list :name "source-db" :status 'pass
             :detail (or health-chart-source-db "biomarker's default database"))))))

(provide 'health-chart-source)
;;; health-chart-source.el ends here

;;; health-chart-backend-test.el --- Chart specs, templates and backends -*- lexical-binding: t; -*-

;; Pure tests pin the chartspec/v1 of every templated kind and the
;; program each backend generates from it (golden files under
;; fixtures/golden/chartspec, /vega-lite and /gnuplot).  Render tests
;; run only when the backend's tool is installed.  Regenerate goldens
;; with HEALTH_CHART_UPDATE_GOLDEN=1 make test and review the diff.

;;; Code:

(require 'health-chart-test-helpers)
(require 'dom)

(defconst health-chart-backend-test--sample
  (expand-file-name "../examples/sample-panel.json" health-chart-test-dir)
  "The synthetic biomarker/v1 sample panel.")

(defun health-chart-backend-test-sample ()
  "The sample panel as canonical measurements."
  (health-chart-source-parse
   (with-temp-buffer
     (let ((coding-system-for-read 'utf-8-unix))
       (insert-file-contents health-chart-backend-test--sample))
     (buffer-string))))

(defun health-chart-backend-test-indicators ()
  "Indicator values evaluated from alex's sample draws, as of a fixed day."
  (let ((ms (health-chart-filter (health-chart-backend-test-sample) :person "alex")))
    (mapcar (lambda (member)
              (apply #'health-chart-indicator-evaluate (car member) ms
                     :as-of "2025-10-01" :cohort "sample" :person "alex" (cdr member)))
            '(("health.cardio.apob") ("health.cardio.lp-a")
              ("health.metabolic.hba1c") ("health.vitamin-d")))))

(defconst health-chart-backend-test--specs
  '((timeseries :person "alex" :marker "ldl-c")
    (panel :person "alex" :marker ("ldl-c" "hdl-c" "vitamin-d" "tsh"))
    (bullet :person "alex")
    (heatmap :person "alex")
    (compare :marker "vitamin-d")
    (delta :person "alex")
    (staleness)
    (trend :person "alex" :marker "ldl-c")
    (lollipop :person "alex" :marker "hscrp")
    (strip :person "alex")
    (dumbbell :person "alex")
    (dual :person "alex" :marker ("glucose" "hba1c"))
    (inrange :person "alex"))
  "Each templated kind with the props its goldens are built with.")

(defun health-chart-backend-test--data (kind)
  "Sample data for KIND."
  (if (eq kind 'staleness) (health-chart-backend-test-indicators)
    (health-chart-backend-test-sample)))

(defmacro health-chart-backend-test-with-templates (dir &rest body)
  "Run BODY with DIR, a fresh temporary directory, first in the template path."
  (declare (indent 1))
  `(let* ((,dir (make-temp-file "hc-templates" t))
          (health-chart-template-directories (list ,dir)))
     (unwind-protect (progn ,@body)
       (delete-directory ,dir t))))

(defun health-chart-backend-test--write (file text)
  "Write TEXT to FILE, creating its directory."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region text nil file nil 'silent)))

;; -----------------------------------------------------------------------
;; Sample data
;; -----------------------------------------------------------------------

(ert-deftest health-chart-backend-test-sample-csv-matches-json ()
  (let* ((csv (with-temp-buffer
                (insert-file-contents (expand-file-name "../examples/sample-panel.csv"
                                                        health-chart-test-dir))
                (split-string (buffer-string) "\n" t)))
         (header (split-string (car csv) ","))
         (ms (health-chart-backend-test-sample)))
    (should (equal header '("person" "marker" "marker_name" "category" "taken_at" "value" "unit"
                            "ref_low" "ref_high" "opt_low" "opt_high" "flag")))
    (should (= (length (cdr csv)) (length ms)))
    (cl-loop for line in (cdr csv) for m in ms
             for cells = (split-string line ",")
             do (should (equal (nth 0 cells) (plist-get m :person)))
             do (should (equal (nth 1 cells) (plist-get m :marker)))
             do (should (equal (nth 4 cells) (plist-get m :date)))
             do (should (= (string-to-number (nth 5 cells)) (plist-get m :value))))
    (should (equal (health-chart-persons ms) '("alex" "sam")))
    (should (= 13 (length (health-chart-markers ms))))
    ;; the story: some markers out of range, some improving into it
    (should (seq-some #'health-chart-out-of-range-p ms))
    (should (equal (plist-get (car (health-chart-filter ms :person "alex" :marker "ldl-c")) :label)
                   "LDL-C"))))

;; -----------------------------------------------------------------------
;; chartspec/v1
;; -----------------------------------------------------------------------

(ert-deftest health-chart-backend-test-spec-round-trips-json ()
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-backend-test--specs)
      (let ((spec (apply #'health-chart-spec kind (health-chart-backend-test--data kind) props)))
        (should (equal (plist-get spec :schema) "chartspec/v1"))
        (should (equal (plist-get spec :kind) (symbol-name kind)))
        (should (> (length (plist-get spec :rows)) 0))
        (should (equal spec (health-chart-spec-from-json (health-chart-spec-to-json spec))))))))

(ert-deftest health-chart-backend-test-spec-goldens ()
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-backend-test--specs)
      (health-chart-test-golden
       (format "chartspec/%s.json" kind)
       (concat (health-chart-spec-to-json
                (apply #'health-chart-spec kind (health-chart-backend-test--data kind) props) t)
               "\n")))))

(ert-deftest health-chart-backend-test-spec-timeseries-content ()
  (health-chart-test-env
    (let* ((spec (health-chart-spec 'timeseries (health-chart-backend-test-sample)
                                    :person "alex" :marker "ldl-c"))
           (rows (plist-get spec :rows))
           (ov (plist-get spec :overlays)))
      (should (equal (plist-get spec :title) "LDL-C · alex"))
      (should (equal (plist-get spec :subtitle) "latest 76 mg/dL on 2025-09-15 · ◐ suboptimal"))
      (should (= 8 (length rows)))
      (should (equal (plist-get (aref rows 0) :status_label) "▲ high"))
      (should (= 1 (plist-get (aref rows 7) :latest)))
      ;; bands: raw bounds and the drawn extents clamped to the y domain
      (should (equal (plist-get ov :ref_high) 100))
      (should (equal (plist-get ov :opt_high) 70))
      (should (equal (plist-get ov :ref_label) "reference 0–100"))
      (should (= 0 (plist-get ov :ref_y)))
      (should (equal (plist-get (aref (plist-get ov :annotations) 0) :text) "latest 76 mg/dL"))
      ;; every legend entry is glyph and word, with a color and a shape
      (should (equal (mapcar (lambda (e) (plist-get e :label)) (plist-get spec :legend))
                     '("◐ suboptimal" "▲ high")))
      (should (cl-every (lambda (e) (and (plist-get e :color) (plist-get e :shape) (plist-get e :pt)))
                        (plist-get spec :legend)))
      ;; the y domain never dips below zero for non-negative values
      (should (>= (aref (plist-get (plist-get spec :y) :domain) 0) 0))
      ;; yearly ticks over a four-year span
      (should (equal (mapcar (lambda (tk) (plist-get tk :label)) (plist-get (plist-get spec :x) :ticks))
                     '("2022" "2023" "2024" "2025"))))))

(ert-deftest health-chart-backend-test-spec-props ()
  (health-chart-test-env
    (let ((spec (health-chart-spec 'timeseries (health-chart-backend-test-sample)
                                   :person "sam" :marker "tsh" :theme 'dark :title "Thyroid"
                                   :pixel-width 900 :ref nil)))
      (should (equal (plist-get spec :title) "Thyroid"))
      (should (equal (plist-get spec :theme) "dark"))
      (should (equal (plist-get (plist-get spec :colors) :surface) "#1a1a19"))
      (should (= (plist-get spec :width) 900))
      (should (null (plist-get (plist-get spec :overlays) :ref_y)))
      (should (plist-get (plist-get spec :overlays) :opt_y)))
    (let ((health-chart-colors '((optimal . "#00ff00"))))
      (should (equal (plist-get (plist-get (health-chart-spec 'bullet (health-chart-backend-test-sample)
                                                              :person "alex")
                                           :colors)
                                :optimal)
                     "#00ff00")))))

(ert-deftest health-chart-backend-test-spec-validates ()
  (health-chart-test-env
    (let ((err (should-error (health-chart-spec 'timeseries '((:marker "x" :date "nope" :value 1)))
                             :type 'health-chart-invalid-data)))
      (should (equal (plist-get (cddr err) :index) 0)))
    (should-error (health-chart-spec-from-json "{\"schema\":\"other\"}") :type 'health-chart-error)))

;; -----------------------------------------------------------------------
;; Templates
;; -----------------------------------------------------------------------

(ert-deftest health-chart-backend-test-fill-escapes-per-language ()
  (let ((ctx '(:title "it's \"x\" `rm -rf` \\n" :n 1.5 :i 3 :none nil
               :list ["a" "b'c"] :nums [1 2.5]
               :rows [(:date "2024-01-01" :value 2 :label "tab\there")
                      (:date "2024-02-01" :value nil :label "`x`")])))
    (should (equal (health-chart-template-fill "{{title}}" ctx 'json)
                   "\"it's \\\"x\\\" `rm -rf` \\\\n\""))
    ;; single quotes: no backslash escapes, no backquote substitution
    (should (equal (health-chart-template-fill "{{title}}" ctx 'gnuplot)
                   "'it''s \"x\" `rm -rf` \\n'"))
    (should (equal (health-chart-template-fill "{{n}} {{i}} {{none}}" ctx 'gnuplot) "1.5 3 NaN"))
    (should (equal (health-chart-template-fill "{{n}} {{i}} {{none}}" ctx 'json) "1.5 3 null"))
    (should (equal (health-chart-template-fill "{{list}}" ctx 'gnuplot) "['a', 'b''c']"))
    (should (equal (health-chart-template-fill "{{list}}" ctx 'json) "[\"a\",\"b'c\"]"))
    (should (equal (health-chart-template-fill "{{nums|length}} {{ rows | length }}" ctx 'gnuplot) "2 2"))
    (should (equal (health-chart-template-fill "{{rows}}" ctx 'gnuplot)
                   "date\tvalue\tlabel\n2024-01-01\t2\ttab here\n2024-02-01\tNaN\t'x'"))
    (should (equal (health-chart-template-fill "{{rows.label}}" ctx 'json) "[\"tab\\there\",\"`x`\"]"))
    (should (equal (health-chart-template-fill "{{rows.1.date}}" ctx 'json) "\"2024-02-01\""))
    (should (equal (health-chart-template-fill "{{i|bare}}" ctx 'gnuplot) "3"))
    (should-error (health-chart-template-fill "{{title|bare}}" ctx 'gnuplot)
                  :type 'health-chart-template-error)
    (should-error (health-chart-template-fill "{{title|shout}}" ctx 'json)
                  :type 'health-chart-template-error)
    ;; not a placeholder: copied as is
    (should (equal (health-chart-template-fill "{{ a b }} {x}" ctx 'json) "{{ a b }} {x}"))))

(ert-deftest health-chart-backend-test-unknown-placeholder-names-file-and-line ()
  (let ((err (should-error (health-chart-template-fill "a\nb {{nope}}" '(:a 1) 'json "/t/x.vl.json")
                           :type 'health-chart-template-error)))
    (should (equal (plist-get (cddr err) :code) "template_unknown_variable"))
    (should (equal (plist-get (cddr err) :line) 2))
    (should (string-match-p "x.vl.json:2: unknown placeholder {{nope}}" (cadr err)))))

(ert-deftest health-chart-backend-test-every-kind-has-both-templates ()
  (health-chart-test-env
    (dolist (kind '(timeseries panel bullet heatmap compare delta staleness
                    trend lollipop strip dumbbell dual inrange))
      (dolist (backend '(vega-lite gnuplot))
        (should (health-chart-template-for backend kind))))
    (should (seq-every-p (lambda (tpl) (eq (plist-get tpl :source) 'bundled)) (health-chart-templates)))))

(ert-deftest health-chart-backend-test-program-goldens ()
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-backend-test--specs)
      (let ((data (health-chart-backend-test--data kind)))
        (let ((vl (apply #'health-chart-render kind data :backend 'vega-lite :format 'vega-lite props)))
          (should (json-parse-string vl))
          (health-chart-test-golden (format "vega-lite/%s.vl.json" kind) vl))
        (health-chart-test-golden
         (format "gnuplot/%s.gp" kind)
         (plist-get (apply #'health-chart-render-explain kind data :backend 'gnuplot :format 'svg props)
                    :program))))))

(ert-deftest health-chart-backend-test-user-template-shadows-and-adds-kinds ()
  (health-chart-test-env
    (health-chart-backend-test-with-templates dir
      (health-chart-backend-test--write
       (expand-file-name "vega-lite/timeseries.vl.json" dir) "{\"mine\": {{title}}}")
      (health-chart-backend-test--write
       (expand-file-name "vega-lite/my-kind.vl.json" dir)
       "{\"data\": {\"values\": {{data}}}, \"mark\": \"point\", \"n\": {{data|length}}}")
      (let ((ms (health-chart-backend-test-sample)))
        (should (equal (health-chart-render 'timeseries ms :backend 'vega-lite :format 'vega-lite
                                            :person "alex" :marker "ldl-c")
                       "{\"mine\": \"LDL-C · alex\"}"))
        ;; a kind known only by its template file
        (let ((out (health-chart-render 'my-kind (health-chart-filter ms :person "sam")
                                        :backend 'vega-lite :format 'vega-lite)))
          (should (= 91 (alist-get 'n (json-parse-string out :object-type 'alist)))))
        (let ((listed (seq-filter (lambda (tpl) (eq (plist-get tpl :source) 'user))
                                  (health-chart-templates))))
          (should (equal (sort (mapcar (lambda (tpl) (plist-get tpl :kind)) listed)
                               (lambda (a b) (string< a b)))
                         '(my-kind timeseries))))
        (should (equal (plist-get (health-chart-explain 'my-kind ms :backend 'vega-lite :format 'vega-lite)
                                  :valid)
                       t))))
    (should-error (health-chart-render 'no-such-kind nil :backend 'vega-lite)
                  :type 'health-chart-unknown-kind)))

;; -----------------------------------------------------------------------
;; Selection and plans
;; -----------------------------------------------------------------------

(ert-deftest health-chart-backend-test-selection ()
  (health-chart-test-env
    (cl-letf (((symbol-function 'health-chart-vega-lite-available-p) (lambda () t))
              ((symbol-function 'health-chart-gnuplot-available-p) (lambda () t))
              ((symbol-function 'health-chart--graphic-context-p) (lambda () t)))
      (should (equal (butlast (health-chart-select-backend 'timeseries)) '(vega-lite svg)))
      (should (equal (butlast (health-chart-select-backend 'timeseries nil 'png)) '(vega-lite png)))
      ;; vega-lite writes no text: a text request goes to the terminal list
      (let ((health-chart-terminal-backends '(gnuplot text)))
        (should (equal (butlast (health-chart-select-backend 'timeseries nil 'text)) '(gnuplot text))))
      ;; kinds with no template are native text
      (should (equal (butlast (health-chart-select-backend 'table)) '(text text)))
      (let ((health-chart-graphic-backends '(gnuplot vega-lite)))
        (should (eq (car (health-chart-select-backend 'heatmap)) 'gnuplot))))
    (cl-letf (((symbol-function 'health-chart-vega-lite-available-p) (lambda () nil))
              ((symbol-function 'health-chart-gnuplot-available-p) (lambda () nil))
              ((symbol-function 'health-chart--graphic-context-p) (lambda () nil)))
      (let ((health-chart-terminal-backends '(gnuplot text)))
        (should (equal (butlast (health-chart-select-backend 'timeseries)) '(text text))))
      (should (equal (butlast (health-chart-select-backend 'timeseries 'gnuplot 'png)) '(gnuplot png)))
      (let ((err (should-error (health-chart-select-backend 'timeseries 'gnuplot 'vega-lite)
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "unsupported_format")))
      (should-error (health-chart-select-backend 'timeseries 'nope) :type 'health-chart-backend-error))))

(ert-deftest health-chart-backend-test-png-where-emacs-lacks-librsvg ()
  (health-chart-test-env
    (cl-letf (((symbol-function 'health-chart-vega-lite-available-p) (lambda () t))
              ((symbol-function 'health-chart--graphic-context-p) (lambda () t))
              ((symbol-function 'image-type-available-p) (lambda (type) (eq type 'png))))
      (should (equal (butlast (health-chart-select-backend 'timeseries)) '(vega-lite png)))
      (should (equal (butlast (health-chart-select-backend 'timeseries 'gnuplot)) '(gnuplot png)))
      ;; nothing installed: the terminal renderer, not an error
      (cl-letf (((symbol-function 'health-chart-vega-lite-available-p) (lambda () nil))
                ((symbol-function 'health-chart-gnuplot-available-p) (lambda () nil)))
        (should (equal (butlast (health-chart-select-backend 'timeseries)) '(text text)))))))

(defun health-chart-backend-test--fake-tool (dir name)
  "Write an executable NAME in DIR printing \"ok\"; return NAME.
On Windows it is a .cmd file, as npm's shims are."
  (if (eq system-type 'windows-nt)
      (health-chart-backend-test--write (expand-file-name (concat name ".cmd") dir)
                                        "@echo off\r\necho ok\r\n")
    (let ((file (expand-file-name name dir)))
      (health-chart-backend-test--write file "#!/bin/sh\necho ok\n")
      (set-file-modes file #o755)))
  name)

(ert-deftest health-chart-backend-test-tools-found-in-tool-directories ()
  (let* ((dir (make-temp-file "hc-tools" t))
         (name (health-chart-backend-test--fake-tool dir "hc-fake-tool"))
         (health-chart-tool-directories nil))
    (unwind-protect
        (progn
          (should-not (health-chart-executable name))
          (let ((err (should-error (health-chart--run (list name) "")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_missing")))
          (let ((health-chart-tool-directories (list dir)))
            (should (file-equal-p (file-name-directory (health-chart-executable name)) dir))
            ;; run by its resolved name, without a shell; CRLF read as LF
            (should (equal (health-chart--run (list name) "") "ok\n"))
            (let ((health-chart-gnuplot-command (list name)))
              (should (health-chart-gnuplot-available-p)))))
      (delete-directory dir t))))

;; gnuplot on Windows exits 0 after a script error, printing nothing
(ert-deftest health-chart-backend-test-empty-output-is-a-failure ()
  (let* ((dir (make-temp-file "hc-tools" t))
         (health-chart-tool-directories (list dir))
         (name "hc-silent"))
    (unwind-protect
        (progn
          ;; exits at once, never reading stdin
          (if (eq system-type 'windows-nt)
              (health-chart-backend-test--write (expand-file-name (concat name ".cmd") dir)
                                                "@echo off\r\necho oops 1>&2\r\n")
            (let ((file (expand-file-name name dir)))
              (health-chart-backend-test--write file "#!/bin/sh\necho oops >&2\n")
              (set-file-modes file #o755)))
          (let ((err (should-error (health-chart--run (list name) "plot x")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_failed"))
            (should (string-match-p "wrote no output: oops" (cadr err))))
          ;; a tool writing its own file owes nothing on stdout
          (should (equal (health-chart--run (list name) "plot x" nil t) "")))
      (delete-directory dir t))))

(ert-deftest health-chart-backend-test-tools-get-stdin-and-time-out ()
  (skip-unless (not (eq system-type 'windows-nt)))
  (let* ((dir (make-temp-file "hc-tools" t))
         (health-chart-tool-directories (list dir))
         (health-chart-render-timeout 1))
    (unwind-protect
        (progn
          (dolist (tool '(("hc-cat" . "#!/bin/sh\ncat\n")
                          ("hc-fail" . "#!/bin/sh\necho 'bad input ✗' >&2\nexit 3\n")
                          ("hc-hang" . "#!/bin/sh\nexec sleep 30\n")))
            (let ((file (expand-file-name (car tool) dir)))
              (health-chart-backend-test--write file (cdr tool))
              (set-file-modes file #o755)))
          (let ((big (concat (make-string 200000 ?x) "ε\n")))
            (should (equal (health-chart--run '("hc-cat") big) big)))
          (should (equal (health-chart--run '("hc-cat") "\211PNG" t) "\211PNG"))
          (let ((err (should-error (health-chart--run '("hc-fail") "")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_failed"))
            (should (equal (plist-get (cddr err) :exit) 3))
            (should (string-match-p "bad input ✗" (cadr err))))
          (let* ((start (float-time))
                 (err (should-error (health-chart--run '("hc-hang") "")
                                    :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_timeout"))
            (should (< (- (float-time) start) 10))))
      (delete-directory dir t))))

(ert-deftest health-chart-backend-test-png-without-rsvg-says-svg-works ()
  (health-chart-test-env
    (let* ((dir (make-temp-file "hc-tools" t))
           (health-chart-tool-directories (list dir))
           (health-chart-vl2svg-command
            (list (health-chart-backend-test--fake-tool dir "hc-fake-vl2svg")))
           (health-chart-vl2png-command '("hc-no-such-vl2png"))
           (health-chart-rsvg-convert-command '("hc-no-such-rsvg-convert"))
           (health-chart-vega-lite-raster 'auto)
           (health-chart--vl-canvas-broken nil))
      (unwind-protect
          (let ((err (should-error (health-chart-render 'bullet (health-chart-backend-test-sample)
                                                        :backend 'vega-lite :format 'png
                                                        :person "alex")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_missing"))
            (should (string-match-p "hc-no-such-vl2png" (cadr err)))
            (should (string-match-p "write SVG" (cadr err)))
            (should-not health-chart--vl-canvas-broken))
        (delete-directory dir t)))))

(ert-deftest health-chart-backend-test-explain-is-a-pure-plan ()
  (health-chart-test-env
    (let* ((ms (health-chart-backend-test-sample))
           (health-chart-vl2svg-command '("vl2svg"))
           (health-chart-vl2png-command '("vl2png"))
           (health-chart-vega-lite-raster 'auto)
           (health-chart--vl-canvas-broken nil)
           (gp (health-chart-explain 'bullet ms :backend 'gnuplot :format 'png :person "alex"))
           (vl (health-chart-render-explain 'bullet ms :backend 'vega-lite :format 'png :person "alex")))
      (should (eq (plist-get gp :backend) 'gnuplot))
      (should (string-suffix-p "templates/gnuplot/bullet.gp" (plist-get gp :template)))
      (should (equal (plist-get (car (plist-get gp :steps)) :argv) health-chart-gnuplot-command))
      (should (string-match-p "set terminal pngcairo size 720," (plist-get gp :program)))
      (should (equal (plist-get gp :points) 195))
      (should (equal (plist-get (car (plist-get vl :steps)) :argv) '("vl2png" "-s" "1")))
      (should (equal (mapcar (lambda (s) (car (plist-get s :argv))) (plist-get vl :fallback))
                     '("vl2svg" "rsvg-convert")))
      (let ((health-chart-vega-lite-raster 'rsvg-convert))
        (should (equal (plist-get (cadr (plist-get (health-chart-render-explain
                                                     'bullet ms :backend 'vega-lite :format 'png
                                                     :scale 2 :person "alex")
                                                    :steps))
                                  :argv)
                       '("rsvg-convert" "-f" "png" "-z" "2"))))
      ;; text is native unless a terminal backend says otherwise
      (should (eq (plist-get (health-chart-explain 'bullet ms :person "alex") :backend) 'text)))))

(ert-deftest health-chart-backend-test-format-from-file-name ()
  (should (eq (health-chart-format-of-file "a/b.PNG") 'png))
  (should (eq (health-chart-format-of-file "c.vl.json") 'vega-lite))
  (should (eq (health-chart-format-of-file "c.txt") 'text))
  (should-error (health-chart-format-of-file "c.gif") :type 'health-chart-backend-error))

(ert-deftest health-chart-backend-test-native-backends-still-render ()
  (health-chart-test-env
    (let ((ms (health-chart-test-ms)))
      (should (string-prefix-p "LDL-C" (health-chart-render 'timeseries ms :backend 'text :format 'text
                                                           :person "alex" :marker "ldl_c")))
      (should (string-prefix-p "<svg" (health-chart-plot 'bullet ms :backend 'svg :person "alex"))))))

;; -----------------------------------------------------------------------
;; Rendering, when the tools are installed
;; -----------------------------------------------------------------------

(defun health-chart-backend-test--png-p (bytes)
  "Non-nil when BYTES start with the PNG signature."
  (and (stringp bytes) (> (length bytes) 8) (string-prefix-p "\211PNG" bytes)))

(ert-deftest health-chart-backend-test-gnuplot-renders ()
  (skip-unless (health-chart-gnuplot-available-p))
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-backend-test--specs)
      (let ((data (health-chart-backend-test--data kind)))
        (let ((svg (apply #'health-chart-render kind data :backend 'gnuplot :format 'svg props)))
          (should (string-match-p "<svg" svg))
          (when (fboundp 'libxml-parse-xml-region)
            (should (with-temp-buffer (insert svg)
                                      (libxml-parse-xml-region (point-min) (point-max))))))
        (should (health-chart-backend-test--png-p
                 (apply #'health-chart-render kind data :backend 'gnuplot :format 'png props)))
        (let ((text (apply #'health-chart-render kind data :backend 'gnuplot :format 'text props)))
          (should (stringp text))
          (should (> (length (split-string text "\n")) 5)))))))

(ert-deftest health-chart-backend-test-vega-lite-renders ()
  (skip-unless (health-chart-vega-lite-available-p))
  (health-chart-test-env
    (pcase-dolist (`(,kind . ,props) health-chart-backend-test--specs)
      (let ((svg (apply #'health-chart-render kind (health-chart-backend-test--data kind)
                        :backend 'vega-lite :format 'svg props)))
        (should (string-prefix-p "<svg" svg))
        ;; status words reach the drawing, never color alone
        (unless (memq kind '(compare delta staleness dumbbell))
          (should (string-match-p "suboptimal\\|optimal\\|high\\|low" svg)))))))

(ert-deftest health-chart-backend-test-vega-lite-png ()
  (skip-unless (and (health-chart-vega-lite-available-p) (health-chart--rsvg-available-p)))
  (health-chart-test-env
    (let ((health-chart-vega-lite-raster 'rsvg-convert))
      (should (health-chart-backend-test--png-p
               (health-chart-render 'bullet (health-chart-backend-test-sample)
                                    :backend 'vega-lite :format 'png :person "alex"))))))

(ert-deftest health-chart-backend-test-write-picks-format-from-extension ()
  (skip-unless (health-chart-gnuplot-available-p))
  (health-chart-test-env
    (let ((dir (make-temp-file "hc-write" t)))
      (unwind-protect
          (let ((ms (health-chart-backend-test-sample)))
            (dolist (ext '("svg" "png" "pdf" "txt"))
              (let ((file (expand-file-name (concat "ts." ext) dir)))
                (should (equal (health-chart-write 'timeseries ms file :backend 'gnuplot
                                                   :person "alex" :marker "ldl-c")
                               file))
                (should (> (file-attribute-size (file-attributes file)) 100))))
            (should (string-prefix-p "%PDF" (health-chart--read-bytes (expand-file-name "ts.pdf" dir))))
            (should (health-chart-backend-test--png-p
                     (health-chart--read-bytes (expand-file-name "ts.png" dir)))))
        (delete-directory dir t)))))

(ert-deftest health-chart-backend-test-backend-errors-carry-stderr ()
  (skip-unless (health-chart-gnuplot-available-p))
  (health-chart-test-env
    (health-chart-backend-test-with-templates dir
      (health-chart-backend-test--write (expand-file-name "gnuplot/timeseries.gp" dir)
                                        "plot $nodata using 1:2\n")
      (let ((err (should-error (health-chart-render 'timeseries (health-chart-backend-test-sample)
                                                    :backend 'gnuplot :format 'svg
                                                    :person "alex" :marker "ldl-c")
                               :type 'health-chart-backend-error)))
        (should (equal (plist-get (cddr err) :code) "backend_failed"))
        (should (string-match-p "gnuplot" (cadr err)))))))

(provide 'health-chart-backend-test)
;;; health-chart-backend-test.el ends here

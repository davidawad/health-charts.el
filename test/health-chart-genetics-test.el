;;; health-chart-genetics-test.el --- Tests for genetics-to-labs links -*- lexical-binding: t; -*-

;;; Commentary:

;; The link table, call normalisation and APOE haplotypes (pure); the
;; `health-genetics-labs' block as golden Org text over the sample panel
;; with a stand-in genetics.el API reading a synthetic 23andMe-format
;; kit; its explain twin; and, when genetics.el is on the load path, the
;; real API.  Synthetic data only.

;;; Code:

(require 'health-chart-test-helpers)
(require 'health-chart-org-test-helpers)
(require 'health-chart-genetics)

(defconst health-chart-genetics-test--kit
  (health-chart-test-fixture "genetics-kit-23andme.txt")
  "The synthetic 23andMe-format kit.")

(defconst health-chart-genetics-test--reference
  '(("rs1801131" . "TT"))
  "Reference genotypes the stand-in infers for SNPs absent from a kit.")

(defun health-chart-genetics-test--read-kit (file)
  "FILE, a 23andMe-format kit, as a hash of rsid -> genotype."
  (let ((kit (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert-file-contents file)
      (dolist (line (split-string (buffer-string) "\n" t))
        (unless (string-prefix-p "#" line)
          (let ((cols (split-string line "\t")))
            (puthash (nth 0 cols) (nth 3 cols) kit)))))
    kit))

(defmacro health-chart-genetics-test-standin (&rest body)
  "Run BODY with a stand-in genetics.el API bound to the configured names.
Kits are read from :file; a SNP the kit lacks but
`health-chart-genetics-test--reference' knows is an inferred reference
call, the way genetics.el reports one."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'genetics-kit)
              (lambda (_name file) (and file (health-chart-genetics-test--read-kit file))))
             ((symbol-function 'genetics-genotype)
              (lambda (kit rsid)
                (let ((g (gethash rsid kit)))
                  (cond (g g)
                        ((assoc rsid health-chart-genetics-test--reference)
                         (list :genotype (cdr (assoc rsid health-chart-genetics-test--reference))
                               :source "inferred-ref")))))))
     (let ((health-chart-genetics-functions '(:kit genetics-kit :genotype genetics-genotype)))
       ,@body)))

(defmacro health-chart-genetics-test-absent (&rest body)
  "Run BODY as if genetics.el were not loaded."
  (declare (indent 0) (debug t))
  `(let ((health-chart-genetics-functions
          '(:kit health-chart-genetics-test--no-kit :genotype health-chart-genetics-test--no-call)))
     ,@body))

(defun health-chart-genetics-test--doc (&rest extra)
  "A document with one `health-genetics-labs' block over the kit, plus EXTRA params.
Copies the kit into the current directory as kit.txt."
  (copy-file health-chart-genetics-test--kit "kit.txt" t)
  (format "* Genetics and labs\n#+BEGIN: health-genetics-labs :person \"alex\" :kit \"demo\" :file \"kit.txt\" :until \"2025-09-30\" :backend text%s\n#+END:\nafter\n"
          (mapconcat (lambda (x) (format " %S" x)) extra "")))

;; -----------------------------------------------------------------------
;; Pure
;; -----------------------------------------------------------------------

(ert-deftest health-chart-genetics-test-link-table ()
  (should (equal (health-chart-genetics-gene-names)
                 '("APOE" "MTHFR" "HFE" "LCT" "F5" "CYP2C19")))
  (dolist (link (health-chart-genetics-links))
    (should (plist-get link :rsids))
    (should (stringp (plist-get link :rationale)))
    (should (string-prefix-p "https://" (cdr (plist-get link :source))))
    (should (or (plist-get link :markers) (plist-get link :note))))
  (should (equal (mapcar #'health-chart-genetics-marker-id
                         (plist-get (health-chart-genetics-link 'apoe) :markers))
                 '("ldl-c" "apob" "lpa" "total-cholesterol")))
  (should-not (plist-get (health-chart-genetics-link "CYP2C19") :markers))
  (let ((err (should-error (health-chart-genetics-link "BRCA9") :type 'health-chart-genetics-error)))
    (should (equal (plist-get (cddr err) :code) "unknown_gene"))
    (should (string-match-p "use one of APOE" (cadr err))))
  (should (cl-every (lambda (r) (memq (plist-get r :status) '(pass skip)))
                    (health-chart-genetics-test-absent (health-chart-genetics-doctor-checks)))))

(ert-deftest health-chart-genetics-test-normalize-call ()
  (should (equal (health-chart-genetics-normalize-call "ct") '(:genotype "CT" :source observed)))
  (should (equal (health-chart-genetics-normalize-call '(:genotype "TT" :source inferred-ref))
                 '(:genotype "TT" :source inferred)))
  (should (equal (health-chart-genetics-normalize-call '(:call "AG" :source "observed"))
                 '(:genotype "AG" :source observed)))
  (dolist (none '(nil "--" "00" "" (:genotype nil)))
    (should-not (health-chart-genetics-normalize-call none))))

(ert-deftest health-chart-genetics-test-apoe-haplotype ()
  (should (equal (health-chart-genetics-apoe-haplotype "TT" "CC") "ε3/ε3"))
  (should (equal (health-chart-genetics-apoe-haplotype "TC" "CC") "ε3/ε4"))
  (should (equal (health-chart-genetics-apoe-haplotype "CC" "CC") "ε4/ε4"))
  (should (equal (health-chart-genetics-apoe-haplotype "TT" "CT") "ε2/ε3"))
  (should (equal (health-chart-genetics-apoe-haplotype "TT" "TT") "ε2/ε2"))
  (should (equal (health-chart-genetics-apoe-haplotype "CT" "CT") "ε2/ε4"))
  (should-not (health-chart-genetics-apoe-haplotype "CC" "TT"))
  (should-not (health-chart-genetics-apoe-haplotype nil "CC")))

(ert-deftest health-chart-genetics-test-calls-standin ()
  (health-chart-genetics-test-standin
    (let ((calls (health-chart-genetics-calls nil health-chart-genetics-test--kit)))
      (should (equal (mapcar (lambda (c) (plist-get c :gene)) calls)
                     (health-chart-genetics-gene-names)))
      (let ((apoe (car calls)) (mthfr (nth 1 calls)) (f5 (nth 4 calls)))
        (should (equal (plist-get apoe :haplotype) "ε3/ε4"))
        (should (eq (plist-get apoe :source) 'observed))
        (should (eq (plist-get mthfr :source) 'mixed))
        (should (equal (health-chart-genetics-call-text mthfr)
                       "rs1801133 AG observed, rs1801131 TT inferred reference"))
        (should-not (plist-get f5 :called))))
    (should-error (health-chart-genetics-calls "nobody" nil) :type 'health-chart-genetics-error))
  (health-chart-genetics-test-absent
    (let ((err (should-error (health-chart-genetics-calls "demo" nil)
                             :type 'health-chart-genetics-error)))
      (should (equal (plist-get (cddr err) :code) "genetics_missing")))))

;; -----------------------------------------------------------------------
;; The block
;; -----------------------------------------------------------------------

(ert-deftest health-chart-genetics-test-block-golden ()
  (health-chart-org-test-env
    (health-chart-genetics-test-standin
      (health-chart-test-golden "org-genetics-labs.org"
                                (health-chart-org-test-update (health-chart-genetics-test--doc))))))

(ert-deftest health-chart-genetics-test-block-without-genetics-golden ()
  (health-chart-org-test-env
    (health-chart-genetics-test-absent
      (health-chart-test-golden "org-genetics-labs-absent.org"
                                (health-chart-org-test-update
                                 (health-chart-genetics-test--doc :genes '("HFE" "LCT") :charts nil))))))

(ert-deftest health-chart-genetics-test-block-is-idempotent ()
  (health-chart-org-test-env
    (health-chart-genetics-test-standin
      (let ((once (health-chart-org-test-update (health-chart-genetics-test--doc))))
        (should (equal once (health-chart-org-test-update once)))))))

(ert-deftest health-chart-genetics-test-block-notes-never-break ()
  (health-chart-org-test-env
    (health-chart-genetics-test-standin
      ;; no kit: one note, labs still listed, disclaimer last
      (let ((out (health-chart-org-test-update
                  "#+BEGIN: health-genetics-labs :person \"alex\" :kit \"nobody\" :genes (\"HFE\") :charts nil\n#+END:\nafter\n")))
        (should (string-match-p "^/Genotypes not shown: genetics.el has no kit nobody" out))
        (should (string-match-p "^- .* · \\*Ferritin\\* " out))
        (should (string-match-p "^/Informational only, not medical advice:.*/\n#\\+END:\nafter$" out)))
      ;; a gene without a call, and a gene without labs, are one line each
      (let ((out (health-chart-org-test-update (health-chart-genetics-test--doc :genes '("F5" "CYP2C19")))))
        (should (string-match-p "^\\*F5\\*: no call at rs6025 in this kit\\. .*\\]\\]$" out))
        (should (string-match-p "^\\*CYP2C19\\* · rs4244285 GG; observed\\. .*Pharmacogenomic.*\\]\\]$" out)))
      ;; a bad param is one comment line
      (let ((out (health-chart-org-test-update
                  "#+BEGIN: health-genetics-labs :genes (\"BRCA9\")\n#+END:\nafter\n")))
        (should (string-match-p "^# health-genetics-labs (unknown_gene): unknown gene BRCA9" out))
        (should (string-match-p "^after$" out))))))

(ert-deftest health-chart-genetics-test-explain-is-pure ()
  (health-chart-org-test-env
    (cl-letf (((symbol-function 'genetics-kit) (lambda (&rest _) (error "Explain called genetics.el")))
              ((symbol-function 'genetics-genotype) (lambda (&rest _) (error "Explain called genetics.el"))))
      (let* ((health-chart-genetics-functions '(:kit genetics-kit :genotype genetics-genotype))
             (health-chart-source-function (lambda (&rest _) (error "Explain fetched data")))
             (org (expand-file-name "report.org"))
             (plan (health-chart-org-explain "health-genetics-labs"
                                             '(:person "alex" :kit "alex" :genes ("APOE" "LCT")
                                                       :until "2025-09-30")
                                             org)))
        (should (eq (plist-get plan :valid) t))
        (should (eq (plist-get (plist-get plan :genetics) :available) t))
        (should (equal (plist-get (plist-get plan :genetics) :kit) '(genetics-kit "alex" nil)))
        (should (equal (mapcar (lambda (g) (plist-get g :gene)) (plist-get plan :genes)) '("APOE" "LCT")))
        (let ((query (plist-get plan :query)))
          (should (eq (plist-get query :command) 'latest))
          (should (equal (plist-get (plist-get query :filter) :marker)
                         '("ldl-c" "apob" "lpa" "total-cholesterol" "cholesterol-total"))))
        (let* ((apoe (car (plist-get plan :genes)))
               (chart (cdr (assoc "ldl-c" (plist-get apoe :charts)))))
          (should (eq (plist-get chart :kind) 'timeseries))
          (should (string-match-p "/report-assets/timeseries-alex-ldl-c-[0-9a-f]\\{8\\}\\.svg\\'"
                                  (plist-get chart :output))))
        (should-not (plist-get (cadr (plist-get plan :genes)) :charts))
        (should (string-match-p "not medical advice" (plist-get plan :disclaimer)))
        (should (stringp (plist-get (health-chart-org-genetics-labs-explain '(:genes ("nope"))) :valid)))
        (should-not health-chart-org-test-calls)))))

(ert-deftest health-chart-genetics-test-block-in-templates ()
  (dolist (name '("full-health-report" "cardiometabolic"))
    (let ((plan (health-chart-org-new-report-explain name "/tmp/r.org" :person "alex"
                                                     :date "2025-10-01")))
      (should (seq-find (lambda (b) (equal (plist-get b :block) "health-genetics-labs"))
                        (plist-get plan :blocks))))))

;; -----------------------------------------------------------------------
;; The real genetics.el, when it is on the load path
;; -----------------------------------------------------------------------

(ert-deftest health-chart-genetics-test-real-genetics-el ()
  (skip-unless (locate-library "genetics"))
  (require 'genetics)
  (when (locate-library "genetics-org") (require 'genetics-org))
  (should (health-chart-genetics-available-p))
  (let ((health-chart-org-test-real-genetics t))
   (health-chart-org-test-env
    (let ((out (health-chart-org-test-update (health-chart-genetics-test--doc :charts nil))))
      (should-not (string-match-p "^# health-genetics-labs" out))
      (should-not (string-match-p "^/Genotypes not shown" out))
      (should (string-match-p "^\\*APOE\\* · ε3/ε4 haplotype" out))
      (should (string-match-p "not medical advice" out))))))

(provide 'health-chart-genetics-test)
;;; health-chart-genetics-test.el ends here

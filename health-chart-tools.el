;;; health-chart-tools.el --- Find and run the external rendering tools -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Locating vl2svg, gnuplot and rsvg-convert, and running them
;; asynchronously with a timeout.  No shell is involved.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-backend)

;; -----------------------------------------------------------------------
;; Running tools
;; -----------------------------------------------------------------------

(defun health-chart-executable (program)
  "The absolute file name of PROGRAM, or nil when it is not installed.
PROGRAM is a name looked up with `executable-find' on variable
`exec-path' then `health-chart-tool-directories' (Windows suffixes such
as .exe and .cmd included), or an absolute file name."
  (or (executable-find program)
      (let ((exec-path (append health-chart-tool-directories exec-path)))
        (executable-find program))))

(defun health-chart--command (custom default-exe &rest npx-tail)
  "Command list: CUSTOM, else DEFAULT-EXE when found, else npx with NPX-TAIL."
  (or custom
      (and (health-chart-executable default-exe) (list default-exe))
      (append '("npx" "--yes" "-p" "vega" "-p" "vega-lite" "-p" "vega-cli") npx-tail)))

(defvar health-chart--vl-canvas-broken nil
  "Non-nil once vl2png/vl2pdf failed and rsvg-convert replaced them.")

(defun health-chart-vega-lite-available-p ()
  "Non-nil when a Vega-Lite renderer is configured or vl2svg is installed."
  (let ((cmd (health-chart--command health-chart-vl2svg-command "vl2svg" "vl2svg")))
    (and (not (equal (car cmd) "npx")) (health-chart-executable (car cmd)) t)))

(defun health-chart-gnuplot-available-p ()
  "Non-nil when gnuplot is installed."
  (and (health-chart-executable (car health-chart-gnuplot-command)) t))

(defun health-chart--rsvg-available-p ()
  "Non-nil when rsvg-convert is installed."
  (and (health-chart-executable (car health-chart-rsvg-convert-command)) t))

(defun health-chart--run (argv input &optional binary writes-file)
  "Run ARGV with INPUT (a string) on stdin; return stdout as a string.
BINARY keeps stdout as raw bytes; text output may end lines in CRLF
\(gnuplot on Windows).  The program is resolved with
`health-chart-executable' and run directly, without a shell; on Windows
Emacs runs an npm .cmd shim through cmd.exe itself.  Signals
`health-chart-backend-error' with stderr when the tool is missing,
fails, times out, or writes nothing to stdout unless WRITES-FILE (the
tool writes its own output file).  gnuplot on Windows exits 0 after a
script error, so empty output is how that failure shows."
  (let ((exe (or (health-chart-executable (car argv))
                 (signal 'health-chart-backend-error
                         (list (format "cannot find %s; install it or customize the backend's command (see `health-chart-doctor')"
                                       (car argv))
                               :code "backend_missing" :argv argv))))
        (errors (generate-new-buffer " *health-chart-stderr*" t)))
    (unwind-protect
        (with-temp-buffer
          (set-buffer-multibyte (not binary))
          (let ((status (health-chart--call exe (cdr argv) input binary errors)))
            (when (and (eql status 0) (= (buffer-size) 0) (not writes-file))
              (signal 'health-chart-backend-error
                      (list (format "%s wrote no output: %s" (string-join argv " ")
                                    (string-trim (with-current-buffer errors (buffer-string))))
                            :code "backend_failed" :argv argv :exit 0)))
            (unless (eql status 0)
              (signal 'health-chart-backend-error
                      (if (eq status 'timeout)
                          (list (format "%s did not finish within %s seconds; raise `health-chart-render-timeout' or check the tool"
                                        (string-join argv " ") health-chart-render-timeout)
                                :code "backend_timeout" :argv argv)
                        (list (format "%s exited %s: %s" (string-join argv " ") status
                                      (string-trim (with-current-buffer errors (buffer-string))))
                              :code "backend_failed" :argv argv :exit status))))
            (buffer-string)))
      (kill-buffer errors))))

(defun health-chart--call (exe args input binary errors)
  "Run EXE with ARGS, INPUT on stdin, stdout into the current buffer.
BINARY keeps stdout as bytes, else it is decoded as UTF-8 with any line
ends; stderr goes to buffer ERRORS.  Return the exit status, or
`timeout' after `health-chart-render-timeout' seconds (the process is
then killed).  An asynchronous process, so the timeout holds even
while the tool blocks."
  (let* ((done nil)
         (process-environment (cons "LC_ALL=C.UTF-8" process-environment))
         (proc (make-process :name "health-chart" :buffer (current-buffer)
                             :command (cons exe args) :connection-type 'pipe
                             :coding (cons (if binary 'binary 'utf-8) 'utf-8-unix)
                             :stderr errors :noquery t
                             :sentinel (lambda (_proc _event) (setq done t))))
         (deadline (+ (float-time) health-chart-render-timeout)))
    (when-let* ((err (get-buffer-process errors)))
      (set-process-coding-system err 'utf-8 'utf-8-unix))
    (unwind-protect
        (progn
          ;; a tool may exit without reading stdin; on Windows the write
          ;; then fails, and its exit status is the answer
          (ignore-error error
            (process-send-string proc input)
            (process-send-eof proc))
          ;; the sentinel runs once stdout has been read to the end; under
          ;; load it can be starved, so a reaped child also ends the wait
          (while (and (not done) (process-live-p proc) (< (float-time) deadline))
            (accept-process-output proc 0.05))
          (if (or done (not (process-live-p proc)))
              (progn
                (while (accept-process-output proc 0.05))
                ;; stderr arrives on its own pipe; drain it too
                (when-let* ((err (get-buffer-process errors)))
                  (while (accept-process-output err 0.05)))
                (process-exit-status proc))
            'timeout))
      (when (process-live-p proc) (delete-process proc))
      (when-let* ((err (get-buffer-process errors))) (delete-process err)))))

(defun health-chart--write-bytes (string file)
  "Write STRING to FILE exactly (raw bytes when unibyte, else UTF-8)."
  (let ((coding-system-for-write (if (multibyte-string-p string) 'utf-8-unix 'binary)))
    (with-temp-file file
      (set-buffer-multibyte (multibyte-string-p string))
      (insert string))))

(defun health-chart--read-bytes (file)
  "Contents of FILE as raw bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'binary))
      (insert-file-contents-literally file))
    (buffer-string)))

(defun health-chart--pipe (commands program binary)
  "Return the output of PROGRAM fed through the plan COMMANDS in turn.
Each step's :argv reads the previous output on stdin.  BINARY keeps the
last output as bytes."
  (let ((input program) (n (length commands)) (i 0))
    (dolist (step commands)
      (cl-incf i)
      (setq input (health-chart--run (plist-get step :argv) input (and binary (= i n))
                                     (plist-get step :writes-file))))
    input))

(defun health-chart--pipe-or-svg-only (commands program binary format primary)
  "Run the fallback COMMANDS on PROGRAM as `health-chart--pipe' with BINARY.
When one of their tools (rsvg-convert) is missing, signal that FORMAT
cannot be made here but SVG can, naming PRIMARY, the direct tool's error."
  (condition-case err
      (health-chart--pipe commands program binary)
    (health-chart-backend-error
     (if (and (equal (plist-get (cddr err) :code) "backend_missing")
              (equal (car (plist-get (cddr err) :argv)) (car health-chart-rsvg-convert-command)))
         (signal 'health-chart-backend-error
                 (list (format "cannot write %s: %s; the fallback through rsvg-convert cannot run either (%s); install rsvg-convert, or write SVG, which needs neither"
                               format (cadr primary) (cadr err))
                       :code "backend_missing" :format format
                       :argv (plist-get (cddr err) :argv)))
       (signal (car err) (cdr err))))))

(defun health-chart--render-plan (plan format out)
  "Run PLAN (from a backend's explain) for FORMAT; write OUT or return a string.
A failing primary run falls back to PLAN's :fallback steps when present."
  (let* ((binary (memq format '(png pdf)))
         (output
          (if (null (plist-get plan :steps))
              (plist-get plan :program)
            (condition-case err
                (health-chart--pipe (plist-get plan :steps) (plist-get plan :program) binary)
              (health-chart-backend-error
               (if-let* ((fallback (plist-get plan :fallback)))
                   (prog1 (health-chart--pipe-or-svg-only fallback (plist-get plan :program)
                                                          binary format err)
                     (setq health-chart--vl-canvas-broken t))
                 (signal (car err) (cdr err))))))))
    (if out
        (progn (health-chart--write-bytes output out) out)
      output)))

(provide 'health-chart-tools)
;;; health-chart-tools.el ends here

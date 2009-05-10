;;; compile-command-default.el --- establish a default for M-x compile

;; Copyright 2008, 2009 Kevin Ryde

;; Author: Kevin Ryde <user42@zip.com.au>
;; Version: 2
;; Keywords: processes
;; URL: http://www.geocities.com/user42_kevin/compile-command-default/
;; EmacsWiki: CompilationMode

;; compile-command-default.el is free software; you can redistribute it
;; and/or modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or (at your
;; option) any later version.
;;
;; compile-command-default.el is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
;; Public License for more details.
;;
;; You can get a copy of the GNU General Public License online at
;; <http://www.gnu.org/licenses>.

;;; Commentary:

;; This spot of code lets you establish a default `compile-command' for
;; M-x compile etc.
;;
;; Each function in `compile-command-default-functions' can contemplate the
;; buffer filename, directory, contents, etc, and decide a compile-command
;; they would apply.  The included functions run perl development or test
;; programs, either directly or through the test harness.
;;
;; The operative part is really just the hack to `hack-local-variables' to
;; get a good point to establish a default.  The list of functions is mainly
;; so they can do weird and wonderful tests for when they apply, and can
;; then build something perhaps with absolute directorys etc.
;;
;; See mode-compile.el for a bigger system geared more towards language
;; compiles like gcc etc.

;;; Install:

;; Add to your .emacs
;;
;;     (require 'compile-command-default)
;;
;; By default it does nothing, you add the functions you like the sound of
;; `compile-command-default-functions'.  For example
;;
;;     (setq compile-command-default-functions
;;           '(compile-command-default-perl-pl))
;;
;; or
;;
;;     (add-hook 'compile-command-default-functions
;;               'compile-command-default-perl-pl)

;;; History:

;; Version 1 - the first version
;; Version 2 - allow .t files in subdirectories of /t/


;;; Code:

;;;###autoload
(defgroup compile-command-default nil "Compile-Command-Default"
  :prefix "compile-command-default-"
  :group 'compilation
  :link  '(url-link
           :tag "compile-command-default.el home page"
           "http://www.geocities.com/user42_kevin/compile-command-default/index.html"))

(defcustom compile-command-default-functions nil
  "Functions calculating default `compile-command' values."
  :type 'hook
  :group 'compile-command-default)

;; This is a defadvice so it's re-run by M-x normal-mode.  An entry in
;; `find-file-hook' for instance doesn't get that.
;;
(defadvice hack-local-variables (after compile-command-default activate)
  (and (not (ad-get-arg 0))  ;; not when doing a "mode-only" local vars crunch
       buffer-file-name      ;; only for file buffers

       ;; leave alone any explicit local variables value in the file;
       ;; must give buffer parameter explicitly for xemacs
       (not (local-variable-p 'compile-command (current-buffer)))

       (let ((result (run-hook-with-args-until-success
                      'compile-command-default-functions)))
         (if result
             (set (make-local-variable 'compile-command) result)))))


(defun compile-command-default-perl-pl ()
  "Set `compile-command' to run perl on a .pl file.
This is designed for use in `compile-command-default-functions'.

The command uses an absolute filename like

    perl /top/dir/foo.pl

so it can be re-run from a different directory (a buffer with a
different current directory) if you've followed an error etc.

See `compile-command-default-perl-t-raw' for running development
or example programs with build and working directories included."

  (and (let ((case-fold-search nil)) ;; not Makefile.PL
         (string-match "\\.pl\\'" buffer-file-name))
       (concat "perl " (shell-quote-argument buffer-file-name))))

(custom-add-option 'compile-command-default-functions
                   'compile-command-default-perl-pl)

(defun compile-command-default-perl-t-harness ()
  "Set `compile-command' to run a perl test harness on a t/*.t file.
This is designed for use in `compile-command-default-functions'.

The command is the same sort of thing \"make test\" from
ExtUtils::MakeMaker will run.  For example

    cd /top/dir; \\
    PERL_DL_NONLAZY=1 perl -MExtUtils::Command::MM \\
      -e \"test_harness(0,'blib/lib','blib/arch')\" t/foo.t

It includes a \"cd\" to the top-level directory where a normal
\"make test\" runs.  An absolute path there means you can re-run
from elsewhere if you follow an error to a different file.

Test files in subdirectory like t/author/bar.t are run
similarly."

  (and (let ((case-fold-search nil)) ;; not .T
         (string-match "/\\(t/.*\\.t\\)\\'" buffer-file-name))
       (let ((topdir   (substring buffer-file-name 0 (match-beginning 1)))
             (filename (substring buffer-file-name (match-beginning 1))))
         (set (make-local-variable 'compile-command)
              (concat "cd " (shell-quote-argument topdir) "; \\\n"
                      "PERL_DL_NONLAZY=1 perl -MExtUtils::Command::MM \\\n"
                      "  -e \"test_harness(0,'blib/lib','blib/arch')\" \\\n"
                      "  " (shell-quote-argument filename))))))

(custom-add-option 'compile-command-default-functions
                   'compile-command-default-perl-t-harness)

(defun compile-command-default-perl-t-raw ()
  "Set compile-command to run a perl t/*.t or devel/*.pl file.
This is designed for use in `compile-command-default-functions'.

The command formed is like

    cd /top/dir; \\
    perl -I /top/dir/lib \\
         -I /top/dir/blib/lib \\
         -I /top/dir/blib/arch \\
         t/foo.t   # or devel/foo.pl, or examples/bar.pl

The \"cd\" means it runs from the toplevel the same as a \"make
test\" does on a .t file.  \"cd\" also means the command can be
re-run from elsewhere if you follow an error to a different
directory.

The -I paths get the work-in-progress code, \"lib\" for the very
latest, and \"blib\" for the most recent \"make\" if you keep .xs
code in the toplevel instead of under the \"lib\" tree.  They're
absolute paths in case the program does a chdir() to elsewhere.

For a .t file this is a raw run, so you see all the output,
without the usual ExtUtils::MakeMaker test harness.  See
`compile-command-default-perl-t-harness' for the harness version.

For reference, the blib.pm module \"-Mblib\" is not used to pick
up the blib directory because it dies if there's no such
directory, which can happen if you're trying some all-perl
\"lib\" code without having run Makefile.PL."

  ;; on macos blib.pm has "blib/$MacPerl::Architecture" instead of
  ;; "blib/arch", dunno if there's any value trying to do the same here
  ;; (with a "-e" or something)
  ;;
  (and (let ((case-fold-search nil)) ;; not .T
         (string-match
          ;; .t file anywhere under /t/, or .pl under /devel or /examples
          "/\\(t/.*\\.t\\|\\(devel\\|examples\\)/[^/]+\\.pl\\)\\'"
          buffer-file-name))
       (let* ((topdir   (substring buffer-file-name 0 (match-beginning 1)))
              (filename (substring buffer-file-name (match-beginning 1)))
              (libdir   (concat topdir "lib"))
              (blibdir  (concat topdir "blib/lib"))
              (archdir  (concat topdir "blib/arch")))
         (set (make-local-variable 'compile-command)
              (concat "cd " (shell-quote-argument topdir) "; \\\n"
                      "perl -I " (shell-quote-argument libdir) " \\\n"
                      "     -I " (shell-quote-argument blibdir) " \\\n"
                      "     -I " (shell-quote-argument archdir) " \\\n"
                      "     " (shell-quote-argument filename))))))

(custom-add-option 'compile-command-default-functions
                   'compile-command-default-perl-t-raw)


(provide 'compile-command-default)

;;; compile-command-default.el ends here

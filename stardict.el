;;; stardict.el --- stardict dictionary library

;; Version: 0.1
;; Keywords: stardict

;; This file is *NOT* part of GNU Emacs

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; A copy of the GNU General Public License can be obtained from this
;; program's author (send electronic mail to andyetitmoves@gmail.com)
;; or from the Free Software Foundation, Inc.,
;; 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

;;; Commentary:

;;; Code:

;;; Dependencies:

(require 'f)
(require 'cl-lib)

;;; Customizeable:

(defcustom stardict-always-persist nil
  "Make dictionary buffer persist.

Set to t, dictionary will stay open after query.

This should be set before loading dictionaries to work.
For debugging purpose mainly."
  :type 'boolean
  :group 'stardict)

(defcustom stardict-defer-load t
  "Lazy load the dictionary files.

Set this variable to t will cause dictionary's file loading delayed until
`stardict-query' is called."
  :type 'boolean
  :group 'stardict)

(defcustom stardict-always-cache t
  "Generate cache file to speed things up.

This will create a cache file in dictionaries' folder to help increase query
speed."
  :type 'boolean
  :group 'stardict)

(defcustom stardict-popup-name "*stardict*"
  "Buffer name of stardict.el popup."
  :type 'string
  :group 'stardict)

(defcustom stardict-popup-timeout 5
  "The timeout of stardict.el popup windows, in seconds."
  :type 'integer
  :group 'stardict)

(defcustom stardict-popup-width 40
  "The width of stardict.el popup windows."
  :type 'integer
  :group 'stardict)

(defcustom stardict-popup-border-width 10
  "Internal border width of stardict.el popup windows."
  :type 'integer
  :group 'stardict)

(defface stardict-popup-face
  '((t (:inherit default)))
  "Face for stardict.el popups."
  :group 'stardict)

;;;Variables

(defvar stardict-dictionary-list (list nil)
  "A list holds all dictionaries' info.

You should modify this list by function `startdict-add-dictionary', but if you
have to, you can modify it manually.

For element is a plist, it has the following format:

\(:lang \"Lang-string\"
 :path path-to-folder
 :filename file-name-in-folder-without-suffix
 :persist boolean
 :name dictionary-name-in-the-ifo-file
 :entry entry-data))

in which, the entry-data is generated by `stardict-open'.")

(defvar stardict--loaded nil
  "Interal variable, used to lazy loading dictionary files.

This variable should not be modified manually.")

(defvar stardict--transient-counter 0
  "Transient function counter for function `stardict-defer-load'.")

(defun stardict-str2int (str)
  "Convert string `STR' to integer.
\x21\x22 => 0x2122"
  (let ((sum 0))
	(mapc (lambda (c)
			(setq sum (+ (* sum #x100)
						 (mod c #x100))))
		  str)
	sum))

(defun stardict-open (dir name &optional nocache)
  "Open stardict dictionary in directory `DIR' with name `NAME'.
When `NOCACHE' is not nil, don't load from cache and save to cache.
The return is used as `DICT' argument in other functions."
  (if nocache (stardict-open-1 dir name)
	(let ((cache (expand-file-name (concat name ".idx.emacs.bz2") dir)) ret)
	  (if (file-exists-p cache)
		  (with-temp-buffer
			(insert-file-contents cache)
			(read (current-buffer)))
		(setq ret (stardict-open-1 dir name))
		(with-temp-buffer
		  (prin1 ret (current-buffer))
		  (write-region nil nil cache))
		ret))))

(defun stardict-open-1 (dir name)
  "Internal function used by `stardict-open'.
`DIR' is dictionary location, `NAME' is dictionary name."
  (let ((ifo  (expand-file-name (concat name ".ifo") dir))
		(idx  (expand-file-name (concat name ".idx") dir))
		(dict (expand-file-name (concat name ".dict") dir))
		(idx-offset-bytes 4)
		(word-count 0)
		ifo-ht idx-ht)
	(unless (file-exists-p idx)
	  (setq idx (concat idx ".gz")))
	(unless (file-exists-p dict)
	  (setq dict (concat dict ".dz")))
	;;(message "List %S" (list idx dict ifo))
	(unless (and (file-exists-p idx)
				 (file-exists-p dict)
				 (file-exists-p ifo))
	  (error "File not found"))
	(setq ifo-ht (make-hash-table :test 'equal))
	(setq idx-ht (make-hash-table :test 'equal))
	;; get info
	(with-temp-buffer
	  (insert-file-contents ifo)
	  (goto-char (point-min))
	  (while (re-search-forward "^\\([a-zA-Z]+\\)=\\(.*\\)$" nil t)
		(puthash (match-string 1) (match-string 2) ifo-ht)))
	(when (gethash "idxoffsetbits" ifo-ht)
	  (setq idx-offset-bytes
			(/ (string-to-number (gethash "idxoffsetbits" ifo-ht)) 8)))
	(setq word-count
		  (string-to-number (gethash "wordcount" ifo-ht)))
	;; get index
	(with-temp-buffer
	  (insert-file-contents idx)
	  (goto-char (point-min))
	  (let ((rpt (make-progress-reporter "read index: " 0 (1- word-count))))
		(dotimes (i word-count)
		  (progress-reporter-update rpt i)
		  (let (p word offset size)
			(re-search-forward "\\([^\x00]+?\\)\x00" nil t)
			(setq p (point))

			(setq word (match-string 1))
			(setq offset
				  (stardict-str2int
				   (buffer-substring-no-properties p
												   (+ p idx-offset-bytes))))
			(setq size
				  (stardict-str2int
				   (buffer-substring-no-properties (+ p idx-offset-bytes)
												   (+ p idx-offset-bytes 4))))
			(forward-char (+ idx-offset-bytes 4))
			(puthash word (cons offset size) idx-ht)
			)))
	  (list ifo-ht idx-ht dict))))

(defun stardict-word-exist-p (dict word)
  "Checkout whether `WORD' existed in `DICT'."
  (gethash word (nth 1 dict)))

(defun stardict-lookup (dict word name)
  "Lookup `WORD' in `DICT', return nil when not found."
  (let ((info (gethash word (nth 1 dict)))
		(file (nth 2 dict))
		buffer
		offset size begin end)
	(when info
	  (setq offset (car info))
	  (setq size (cdr info))
	  ;; find any opened dict file
	  (dolist (buf (buffer-list))
		(when (equal file (buffer-file-name buf))
		  (setq buffer buf)))
	  (if buffer
		  (with-current-buffer buffer
			(concat "->> " name " :" "\n"
					(buffer-substring-no-properties (byte-to-position (1+ offset))
													(byte-to-position (+ 1 offset size)))))
		(with-temp-buffer
		  (insert (concat "->> " name " :" "\n"))
		  (insert-file-contents (nth 2 dict) nil offset (+ offset size))
		  (buffer-string))))))

(defun stardict-open-dict-file (dict)
  "Open dict file of `DICT' in Emacs to speed up word lookup.
You should close the dict file yourself."
  (with-current-buffer (find-file-noselect (nth 2 dict))
	(setq buffer-read-only t)))

(defun stardict-get-dict-name (path)
  "Given the `PATH' to dictionary's ifo file, return dictionary name."
  (with-temp-buffer
	(insert-file-contents path)
	(setq buffer-read-only t)
	(goto-char (point-min))
	(when (re-search-forward "bookname=\\(.*\\)")
	  (match-string 1))))

(defun stardict-query (word plist)
  "Search `WORD' using `PLIST', return a message when not found."
  (let ((dict (plist-get plist :entry))
		(name (plist-get plist :name))
		(persist? (plist-get plist :persist))
		(word (or word "test")))
	(when (plist-get plist :persist)
	  (stardict-open-dict-file dict))
	(if (stardict-word-exist-p dict word)
		(concat (stardict-lookup dict word name) "\n")
	  (format "%s" (concat "The word: [" word "] is not found in " name "\n")))))

(defun stardict-collect-result (word dict-list)
  "Search `WORD' through all dictionaries provided by `DICT-LIST' and return."
  (let (result)
	(dolist (dict dict-list result)
	  (setq result (concat result (stardict-query word dict))))))

(defun stardict-group-filter-lang (dict-list lang)
  "Filter out the input `DICT-LIST' by :lang property with value LANG."
  (mapcar (lambda (dict)
			(when (equal (plist-get dict :lang) lang) dict))
		  dict-list))

(defun stardict-prompt-input ()
  "Prompt input object for translate."
  (read-string (format "Translate word (%s): " (or (stardict-dwim) ""))
               nil nil
               (stardict-dwim)))

(defun stardict-dwim ()
  "Return clipbaord content, if none, return region or word around point.

Get clipbaord content if none, check `mark-active'.
If `mark-active' on, return region string.
Otherwise return word around point."
  (let ((target (gui--selection-value-internal 'CLIPBOARD)))
	(if mark-active
		(buffer-substring-no-properties (region-beginning)
										(region-end))
	  (if (thing-at-point 'word)
		  (thing-at-point 'word)
		(format "%s" target)))))

;;;###autoload
(defun stardict-add-dictionary (&rest args)
  "Helper function to add one dictionary at a time.

ARGS is a plist holds basic info about a dictionary.
Example:

\(stardict-add-dictionary :lang \"Eng\"
						  :path \"~/.stardict/dic/stardict-lazyworm-ec-2.4.2/\"
						  :filename \"lazyworm-ec\"
						  :persist t)"
  (interactive)
  (let* ((lang (plist-get args :lang))
		(path (plist-get args :path))
		(filename (plist-get args :filename))
		(persist? (plist-get args :persist))
		(realp (expand-file-name (concat filename ".ifo") path)))
	(if (stringp lang)
		(if (f-directory-p path)
			(if (f-file-p realp)
				(let ((entry (stardict-open path filename stardict-always-cache))
					  (name (stardict-get-dict-name realp)))
				  (push (list :lang lang :path path :filename filename
							  :persist persist? :name name
							  :entry entry) stardict-dictionary-list)
				  (when (and (not stardict-defer-load) (or stardict-always-persist persist?))
					(stardict-open-dict-file entry)))
			  (message "stardict.el: !!! ERROR Dictionary file not exit !!!"))
		  (message "stardict.el: !!! ERROR Language name should be strings !!!")))))

;;;###autoload
(defun stardict-translate (word &optional dict-list)
  "Translate `WORD' with dictionaries in `DICT-LIST', return in minibuffer.

If `DICT-LIST' is not given, default to `stardict-dictionary-list'."
  (let ((dict-list (or dict-list stardict-dictionary-list)))
	(stardict-collect-result word dict-list)))

;;;###autoload
(defun stardict-translate--popup (word &optional dict-list)
  "Translate `WORD', show result by a posframe popup.

Optional `DICT-LIST' defaults to `stardict-dictionary-list'."
  (let* ((dict-list (or dict-list stardict-dictionary-list))
		 (result (stardict-collect-result word dict-list))
		 (posframe-mouse-banish nil))
	(posframe-show
	 stardict-popup-name
	 :string (format "%s" result)
	 :position (point)
	 :timeout stardict-popup-timeout
	 :background-color (face-attribute 'stardict-popup-face :foreground)
	 :foreground-color (face-attribute 'stardict-popup-face :background)
	 :internal-border-width stardict-popup-border-width
	 :width stardict-popup-width
	 :tab-line-height 0
	 :header-line-height 0)
	(unwind-protect
		(push (read-event " ") unread-command-events)
	  (posframe-delete stardict-popup-name))))

;;;###autoload
(defun stardict-translate-popup (&optional word dict-list)
  "Use `stardict-translate--popup' to translate WORD, provide a prompt.

Optional `DICT-LIST' defaults to `stardict-dictionary-list'."
  (interactive)
  (stardict-translate--popup (or word (stardict-prompt-input)) dict-list))

;;;###autoload
(defun stardict-translate-minibuffer (&optional word dict-list)
  "Use `stardict-translate' to translate WORD, provide a prompt.

Optional `DICT-LIST' defaults to `stardict-dictionary-list'."
  (interactive)
  (message "%s" (stardict-translate (or word (stardict-prompt-input)) dict-list)))

;;;###autoload
(defmacro stardict-defer-load (trigger-funcs &rest forms)
  "Add a self-removing function to TRIGGER-FUNCS.

FORMS are evaluated once, before when any functions in TRIGGER-FUNCS is first
invoked, then never again.

TRIGGER-FUNCS is a list of sharp-quoted functions.

This macro is for adding a transient trigger to invoke dictionary indexing
process, so that user can defer the indexing."

  (declare (indent 1))
  (let ((fn (intern (format "stardict--transient-%d-h" (cl-incf stardict--transient-counter)))))
	`(let ()
	   (defun ,fn (&rest _)
		 ,@forms
		 (mapc (lambda (trigger) (advice-remove trigger #',fn)) ,trigger-funcs)
		 (unintern ',fn nil))
	   (mapc (lambda (trigger) (advice-add trigger :before #',fn)) ,trigger-funcs))))

(provide 'stardict)

;;; stardict.el ends here

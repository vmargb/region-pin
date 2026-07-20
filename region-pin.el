;;; region-pin.el --- Syntax-highlighted code snippets, pinned over your buffer -*- lexical-binding: t; -*-

;; Author: vmargb
;; Version: 0.2.2
;; Package-Requires: ((emacs "26.1"))
;; Keywords: convenience, tools

;;; Commentary:

;; This lets you save a named snippet once and then show a floating
;; syntax-highlighted, read-only copy of it in the corner of your window
;; In terminal Emacs (which can't create child frames) it automatically
;; falls back to a small window docked to the top of the frame.
;;
;; Usage:
;;   1. Select a region
;;   2. M-x region-pin-save with a name
;;   3. M-x region-pin-show `completing-read' over saved pin names
;;   4. M-x region-pin-hide toggles the visibility on and off.
;;
;; Pins persist across Emacs restarts `region-pin-save-file'
;;

;;; Code:

(require 'subr-x)

(defgroup region-pin nil
  "Floating code snippets over your buffer."
  :group 'convenience
  :prefix "region-pin-")

(defcustom region-pin-save-file
  (expand-file-name "region-pin/pins.el" user-emacs-directory)
  "File where saved pins are persisted between Emacs sessions."
  :type 'file
  :group 'region-pin)

(defcustom region-pin-max-height 20
  "Maximum number of lines of the floating preview."
  :type 'integer
  :group 'region-pin)

(defcustom region-pin-max-width 80
  "Maximum number of columns of the floating ppeview.
It never stretches to fill the window."
  :type 'integer
  :group 'region-pin)

(defcustom region-pin-position 'top-right
  "Which corner of the window the floating preview is on."
  :type '(choice (const :tag "Top right"  top-right)
                  (const :tag "Top left"   top-left)
                  (const :tag "Top center" top-center))
  :group 'region-pin)

(defcustom region-pin-margin 12
  "Pixel gap between the floating preview and the window edge."
  :type 'integer
  :group 'region-pin)

(defcustom region-pin-header-icon "📌"
  "Icon shown in the pin previews header line."
  :type 'string
  :group 'region-pin)

(defface region-pin-border-face
  '((((background dark)) :background "#444444")  ;; dark theme border
    (((background light)) :background "#cccccc") ;; light theme border
    (t :inherit shadow))                         ;; fallback
  "Face used for the border color."
  :group 'region-pin)

(defcustom region-pin-border-width 1
  "Width of the border around the floating preview in pixels."
  :type 'integer
  :group 'region-pin)

(defvar region-pin--pins (make-hash-table :test 'equal)
  "Hash table mapping pin name (string) to a plist of its saved data.
Plist keys: :text :mode :file :line :date.")

(defvar region-pin--frame nil
  "The reused child frame used to float pin previews (GUI).")

(defvar region-pin--window nil
  "The window currently showing a pin preview (terminal fallback).")

(defvar region-pin--backend nil
  "Which backend is currently displaying a pin: `frame' or `window'.")

(defvar region-pin--current-name nil
  "Name of the pin currently being previewed, if there is any.")

(defvar region-pin--last-name nil
  "Name of the last pin that was previewed.")

(defvar region-pin--last-pin nil
  "Data of the last pin that was previewed.")

(defconst region-pin--buffer-name " *region-pin*"
  "Name of the (single, reused) buffer used to render pin.")

;;; Persistence

(defun region-pin--load ()
  "Load saved pins from `region-pin-save-file', if it exists."
  (when (file-exists-p region-pin-save-file)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents region-pin-save-file)
          (let ((alist (read (current-buffer)))
                (table (make-hash-table :test 'equal)))
            (dolist (pair alist)
              (puthash (car pair) (cdr pair) table))
            (setq region-pin--pins table)))
      (error
       (message "region-pin: could not read %s (%s), starting fresh"
                region-pin-save-file (error-message-string err))))))

(defun region-pin--save-to-disk ()
  "Persist `region-pin--pins' to `region-pin-save-file'."
  (let ((dir (file-name-directory region-pin-save-file))
        (alist nil))
    (when (and dir (not (file-directory-p dir)))
      (make-directory dir t))
    (maphash (lambda (k v) (push (cons k v) alist)) region-pin--pins)
    (with-temp-file region-pin-save-file
      (let ((print-length nil)
            (print-level nil))
        (prin1 alist (current-buffer))))))

;;; Helpers

(defun region-pin--default-name (text)
  "Suggest a pin name from the first non-blank line of TEXT."
  (let* ((first-line (car (split-string (string-trim text) "\n")))
         (trimmed (string-trim (or first-line ""))))
    (if (> (length trimmed) 40)
        (concat (substring trimmed 0 40) "...")
      trimmed)))

(defun region-pin--names ()
  "Return the list of saved pin names."
  (let (names)
    (maphash (lambda (k _v) (push k names)) region-pin--pins)
    (nreverse names)))

(defun region-pin--completing-read ()
  "Prompt for a saved pin name via `completing-read'."
  (let ((names (region-pin--names)))
    (unless names
      (user-error "No pins saved yet, use `region-pin-save' first"))
    (completing-read "Pin: " names nil t)))

(defun region-pin--index-of (elt list)
  "Return the index of ELT in LIST (via `equal'), or nil."
  (let ((i 0) found)
    (while (and list (not found))
      (if (equal elt (car list))
          (setq found i)
        (setq i (1+ i) list (cdr list))))
    found))

;;; Saving

;;;###autoload
(defun region-pin-save (&optional name)
  "Save the active region with NAME, syntax-highlighted pin."
  (interactive)
  (unless (use-region-p)
    (user-error "No active region to pin"))
  (let ((beg (region-beginning))
        (end (region-end)))
    ;; make sure the region is actually fontified before copying
    ;; if it was never displayed, font-lock may not have run over it yet
    (if (fboundp 'font-lock-ensure)
        (font-lock-ensure beg end)
      (with-no-warnings (font-lock-fontify-region beg end)))
    (let* ((text (buffer-substring-no-properties beg end))
           (default-name (region-pin--default-name text))
           (name (or name
                     (read-string (format "Pin name (%s): " default-name)
                                  nil nil default-name))))
      (puthash name
               (list :text text
                     :mode major-mode
                     :file (or (buffer-file-name) (buffer-name))
                     :line (line-number-at-pos beg)
                     :date (format-time-string "%Y-%m-%d %H:%M"))
               region-pin--pins)
      (region-pin--save-to-disk)
      (deactivate-mark)
      (message "Pinned region as \"%s\"" name))))

;;;###autoload
(defun region-pin-instant ()
  "Immediately display the active region as a floating pin.
Unlike `region-pin-save', this does not persist the pin to disk."
  (interactive)
  (unless (use-region-p)
    (user-error "No active region to pin"))
  (let ((beg (region-beginning))
        (end (region-end)))
    (if (fboundp 'font-lock-ensure)
        (font-lock-ensure beg end)
      (with-no-warnings (font-lock-fontify-region beg end)))
    (let* ((text (buffer-substring-no-properties beg end))
           (pin (list :text text
                      :mode major-mode
                      :file (or (buffer-file-name) (buffer-name))
                      :line (line-number-at-pos beg)
                      :date (format-time-string "%Y-%m-%d %H:%M"))))
      (deactivate-mark)
      (region-pin--display nil pin))))

;;; Follow and show region (using dumb-jump)

(defcustom region-pin-follow-lines 10
  "Fallback number of lines to grab when defun bounds can't be found.
Used by `region-pin-follow' when `beginning-of-defun'/`end-of-defun' fails."
  :type 'integer
  :group 'region-pin)

(defun region-pin--dumb-jump-candidate-string (item)
  "Format ITEM (`xref-item') as a human-readable completion candidate."
  (let* ((loc (xref-item-location item))
         (file (xref-location-group loc))
         (line (xref-location-line loc))
         (summary (string-trim (or (xref-item-summary item) ""))))
    (format "%-40s %s"
            (format "%s:%s" (if file (file-relative-name file) "?") (or line "?"))
            summary)))

(defun region-pin--dumb-jump-choose (items id)
  "Return one of ITEMS (from `xref-item') for identifier ID.
If there's only one candidate, return it directly.  Otherwise prompt
with `completing-read', showing each candidate's file, line, and a
snippet of the matched line so you can tell them apart."
  (if (null (cdr items))
      (car items)
    (let* ((alist (mapcar (lambda (it)
                            (cons (region-pin--dumb-jump-candidate-string it) it))
                          items))
           (choice (completing-read
                    (format "%d matches for \"%s\", pick one: " (length items) id)
                    alist nil t)))
      (cdr (assoc choice alist)))))

(defun region-pin--dumb-jump-marker (&optional identifier)
  "Look up IDENTIFIER (symbol at point) with xref.
Uses whichever backend `xref-find-backend' picks, the same one
`xref-find-definitions' (M-.) could be either LSP or dumb-jump."
  (require 'xref)
  (save-excursion ; avoid movement
    (save-window-excursion ; avoid window/buffer switch
      (let* ((backend (or (xref-find-backend) ; find the best possible option first
                           (progn
                             (unless (require 'dumb-jump nil t)
                               (user-error "region-pin-follow needs the `dumb-jump' package installed"))
                             'dumb-jump)))
             (id (or identifier (xref-backend-identifier-at-point backend))))
        (unless id
          (user-error "No identifier at point"))
        (let ((items (xref-backend-definitions backend id)))
          (unless items
            (user-error "No definition found for \"%s\"" id))
          (xref-location-marker
           (xref-item-location (region-pin--dumb-jump-choose items id))))))))

(defun region-pin--grab-defun-at (marker)
  "Return (TEXT . MODE) captured at MARKER.
Gets whole definition via `beginning-of-defun'/`end-of-defun',
`beginning-of-defun' isn't always reliable, falls back to a flat
`region-pin-follow-lines' line grab, anchored at MARKER."
  (with-current-buffer (marker-buffer marker)
    (save-excursion
      (let ((pos (marker-position marker))
            beg end)
        (goto-char pos)
        (forward-line 1) ; prevents walking to previous defun
        ;; grabs beginning and end of defun
        (condition-case nil
            (progn
              (beginning-of-defun)
              (setq beg (point))
              (end-of-defun)
              (forward-line 1) ; grabs last truncated line
              (setq end (point)))
          (error (setq beg nil)))
        ;; falback to grabbing first n lines instead
        (unless (and beg end
                     (<= beg pos end)
                     (<= (count-lines beg end) (* 4 region-pin-follow-lines)))
          (goto-char pos)
          (setq beg (line-beginning-position))
          (forward-line region-pin-follow-lines)
          (setq end (point)))
        ;; make sure the captured region is actually fontified before
        ;; copying, same reasoning as in `region-pin-save'
        (if (fboundp 'font-lock-ensure)
            (font-lock-ensure beg end)
          (with-no-warnings (font-lock-fontify-region beg end)))
        (cons (buffer-substring beg end) major-mode)))))

;;;###autoload
(defun region-pin-follow (&optional identifier)
  "Find IDENTIFIER via dumb-jump and pin it.
Looks up the definition using `dumb-jump', grabs a snippet from there,
like `region-pin-instant', the pin is not persisted to disk."
  (interactive)
  (let* ((marker (region-pin--dumb-jump-marker identifier))
         (text-mode (region-pin--grab-defun-at marker))
         (text (car text-mode))
         (file (buffer-file-name (marker-buffer marker)))
         (line (with-current-buffer (marker-buffer marker)
                 (line-number-at-pos (marker-position marker))))
         (pin (list :text text
                    :mode (cdr text-mode)
                    :file (or file (buffer-name (marker-buffer marker)))
                    :line line
                    :date (format-time-string "%Y-%m-%d %H:%M"))))
    (region-pin--display nil pin)))


;;; Sizing

(defun region-pin--content-cols-rows (buf)
  "Return (COLS . ROWS) that BUFs content actually needs.
capped by max width and height."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let ((max-len 0) (lines 0))
        (while (not (eobp))
          (setq max-len (max max-len (- (line-end-position) (line-beginning-position))))
          (setq lines (1+ lines))
          (forward-line 1))
        (cons (min region-pin-max-width (max 8 (1+ max-len)))
              (min region-pin-max-height (max 1 lines)))))))

;;; Buffer content shared by both backends

(defun region-pin--header-label (name pin)
  "Return the header label for NAME/PIN.
NAME is nil for ephemeral pins (`region-pin-instant', `region-pin-follow')"
  (or name
      (let ((file (plist-get pin :file))
            (line (plist-get pin :line)))
        (format "%s:%s" (if file (file-name-nondirectory file) "unnamed") (or line "?")))))

(defun region-pin--populate-buffer (buf name pin)
  "Fill BUF with the preview content for NAME/PIN."
  (with-current-buffer buf
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (plist-get pin :text))
      (goto-char (point-min)))
    (setq header-line-format
          (if (string-empty-p region-pin-header-icon)
              nil
            (format " %s %s" region-pin-header-icon (region-pin--header-label name pin))))
    (setq mode-line-format nil)
    (setq truncate-lines t)
    (setq-local cursor-type nil)
    (setq-local cursor-in-non-selected-windows nil)
    (setq-local vertical-scroll-bar nil)
    (setq buffer-read-only t)))

;; =============================================
;; main backend: floating child frame (GUI)

(defun region-pin--apply-border (frame)
  "Set FRAME's border color from `region-pin-border-face'."
  (let ((color (face-background 'region-pin-border-face nil t)))
    (set-face-background 'internal-border color frame)
    (when (facep 'child-frame-border)
      (set-face-background 'child-frame-border color frame))))

(defun region-pin--ensure-frame (target)
  "Return a live child frame parented to TARGET.
`parent-frame' is only set at creation time, if the existing frame belongs to a
different parent than TARGET, it's deleted and recreated instead of reparented."
  (when (and (frame-live-p region-pin--frame)
             (not (eq (frame-parameter region-pin--frame 'parent-frame) target)))
    (ignore-errors (delete-frame region-pin--frame))
    (setq region-pin--frame nil))
  (unless (frame-live-p region-pin--frame)
    (setq region-pin--frame
          (make-frame
           `((parent-frame . ,target)
             (minibuffer . nil)
             (visibility . nil)
             (no-accept-focus . t)
             (no-focus-on-map . t)
             (undecorated . t)
             (unsplittable . t)
             (no-other-frame . t)
             (skip-taskbar . t)
             (cursor-type . nil)
             (menu-bar-lines . 0)
             (tool-bar-lines . 0)
             (tab-bar-lines . 0)
             (vertical-scroll-bars . nil)
             (horizontal-scroll-bars . nil)
             (left-fringe . 4)
             (right-fringe . 4)
             (internal-border-width . ,region-pin-border-width))))
    (region-pin--apply-border region-pin--frame))
  ;; dynamically update width and color in case they changed since creation
  (set-frame-parameter region-pin--frame 'internal-border-width region-pin-border-width)
  (region-pin--apply-border region-pin--frame)
  region-pin--frame)

(defun region-pin--frame-position (frame)
  "Return (LEFT . TOP) pixel position, relative to the parent FRAME."
  (let* ((parent (frame-parent frame))
         (win (frame-selected-window parent))
         (win-left (window-pixel-left win))
         (win-top (window-pixel-top win))
         (win-width (window-pixel-width win))
         ;; pixel width replaces manual 'cols * cw'
         (px-width (frame-pixel-width frame))
         (px-height (frame-pixel-height frame))
         (margin region-pin-margin))
    (pcase region-pin-position
      ('top-right (cons (+ win-left (max margin (- win-width px-width margin))) (+ win-top margin)))
      ('top-left (cons (+ win-left margin) (+ win-top margin)))
      ('top-center (cons (+ win-left (max margin (/ (- win-width px-width) 2))) (+ win-top margin)))
      (_ (cons (+ win-left margin) (+ win-top margin))))))

(defun region-pin--display-frame (buf)
  "Float BUF in a child frame parented to the currently selected frame."
  (let* ((target (selected-frame))
         (frame (region-pin--ensure-frame target))
         (cols-rows (region-pin--content-cols-rows buf))
         (cols (car cols-rows))
         (rows (cdr cols-rows)))
    (set-window-buffer (frame-root-window frame) buf)
    (set-window-dedicated-p (frame-root-window frame) t)
    (set-frame-size frame cols (1+ rows))
    ;; pass just the frame, it already knows its own pixel dimensions
    (let ((pos (region-pin--frame-position frame)))
        (set-frame-position frame (car pos) (cdr pos)))
    (make-frame-visible frame)
    ;; shifts focus to the child frame
    ;; force it back so keyboard input keeps going to the code
    (unless (eq (selected-frame) target)
      (select-frame target))
    (setq region-pin--backend 'frame)))

;; ===========================================
;; docked top window (terminal Emacs fallback)

(defun region-pin--display-window (buf)
  "Show BUF docked in a small window pinned to the top of the frame."
  (let ((height (cdr (region-pin--content-cols-rows buf))))
    (setq region-pin--window
          (display-buffer
           buf
           `((display-buffer-reuse-window display-buffer-in-side-window)
             (side . top)
             (slot . 0)
             (window-height . ,(1+ height))
             (dedicated . t)
             (window-parameters . ((no-delete-other-windows . t)
                                    (no-other-window . t))))))
    (setq region-pin--backend 'window)))

;;; Dispatch

(defun region-pin--display (name pin)
  "Render NAME/PIN using whichever backend fits the current display."
  (setq region-pin--current-name name)
  (setq region-pin--last-name name)
  (setq region-pin--last-pin pin)
  (let ((buf (get-buffer-create region-pin--buffer-name)))
    (region-pin--populate-buffer buf name pin)
    (if (display-graphic-p)
        (condition-case err
            (region-pin--display-frame buf)
          (error
           (message "region-pin: floating preview failed (%s), using a docked window instead"
                    (error-message-string err))
           (region-pin--display-window buf)))
      (region-pin--display-window buf))))

;;;###autoload
(defun region-pin-show (name)
  "Float the saved pin NAME over the corner of your window.
Calling this again with the pin already showing hides it (toggle)."
  (interactive (list (region-pin--completing-read)))
  (if (and (equal name region-pin--current-name)
           (or (and (eq region-pin--backend 'frame) (frame-live-p region-pin--frame)
                    (frame-visible-p region-pin--frame))
               (and (eq region-pin--backend 'window) (window-live-p region-pin--window))))
      (region-pin-hide t)
    (let ((pin (gethash name region-pin--pins)))
      (unless pin (user-error "No pin named \"%s\"" name))
      (region-pin--display name pin))))

;;;###autoload
(defun region-pin-hide (&optional force-hide)
  "Toggle the visibility of the region-pin preview.
With optional prefix argument FORCE-HIDE, only hide and do not toggle."
  (interactive "P")
  (let ((visible (or (and (eq region-pin--backend 'frame)
                          (frame-live-p region-pin--frame)
                          (frame-visible-p region-pin--frame))
                     (and (eq region-pin--backend 'window)
                          (window-live-p region-pin--window)))))
    (if (or visible force-hide)
        (progn
          (pcase region-pin--backend
            ('frame (when (frame-live-p region-pin--frame)
                      (make-frame-invisible region-pin--frame)))
            ('window (when (window-live-p region-pin--window)
                       (delete-window region-pin--window)
                       (setq region-pin--window nil)))))
      (when region-pin--last-pin
        (region-pin--display region-pin--last-name region-pin--last-pin)))))

(defun region-pin--cycle (direction)
  "Move to the next (DIRECTION 1) or previous (DIRECTION -1) pin."
  (let* ((names (sort (region-pin--names) #'string<))
         (pos (region-pin--index-of region-pin--current-name names))
         (n (length names)))
    (when (and pos (> n 1))
      (let* ((new-pos (mod (+ pos direction) n))
             (new-name (nth new-pos names)))
        (region-pin--display new-name (gethash new-name region-pin--pins))))))

(defun region-pin-next ()
  "Show the next pin (alphabetically) while a pin is showing."
  (interactive)
  (region-pin--cycle 1))

(defun region-pin-previous ()
  "Show the previous pin (alphabetically) while a pin is showing."
  (interactive)
  (region-pin--cycle -1))

;;;###autoload
(defun region-pin-delete (name)
  "Delete the saved pin NAME."
  (interactive (list (region-pin--completing-read)))
  (remhash name region-pin--pins)
  (region-pin--save-to-disk)
  (message "Deleted pin \"%s\"" name))

(defun region-pin-delete-current ()
  "Delete the pin currently being previewed, and hide the preview."
  (interactive)
  (when region-pin--current-name
    (region-pin-delete region-pin--current-name)
    (region-pin-hide t)))

;;;###autoload
(defun region-pin-clear-all ()
  "Delete every saved pin, after confirming."
  (interactive)
  (when (yes-or-no-p "Delete ALL saved pins? ")
    (clrhash region-pin--pins)
    (region-pin--save-to-disk)
    (region-pin-hide t)
    (message "All pins deleted.")))

;; load any previously saved pins as soon as the package is loaded
(region-pin--load)

(provide 'region-pin)
;;; region-pin.el ends here

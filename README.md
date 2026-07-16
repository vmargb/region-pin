# region-pin.el

<div align="center">
  <img src="region-pin-example.png" alt="region-pin demo" width="800"/>
  <p><em><code>region-pin</code> demo</em></p>
  <br>
</div>

---

## The problem it solves:
You're editing a function that uses a long struct, function (or any other chunk of code)
defined far away in your code or in another file, and you keep
jumping back and forth to remember the field or arg names. `region-pin` lets you save
that snippet once under a name, then preview a syntax-highlighted
floating preview of it in the corner of the window. 

### Why not just split the window?

This was the design of *v0.1.0*, and it wastes space. A full-width split
ends up showing a huge blank margin of wasted space next to the snippet you actually want.
Not to mention, when you already have a window split, adding an additional
one becomes inconvenient.

Instead, a `region-pin` *floats* at the top of the frame regardless of your window configuration.

However, in terminal Emacs, it automatically falls back to the
small window split docked to the top of the frame since it can't create
child frames.

## Install

```elisp
(use-package region-pin
  :vc (:url "https://github.com/vmargb/region-pin/"))
```

Or with `use-package` + `:load-path`:

```elisp
(use-package region-pin
  :load-path "~/path/to/region-pin/")
```

## Keybindings

```elisp
(global-set-key (kbd "C-c p p") #'region-pin-save)
(global-set-key (kbd "C-c p s") #'region-pin-show)
(global-set-key (kbd "C-c p h") #'region-pin-hide)
(global-set-key (kbd "C-c p n") #'region-pin-next)
(global-set-key (kbd "C-c p P") #'region-pin-previous)
(global-set-key (kbd "C-c p d") #'region-pin-delete)
```

## Customization

```elisp
(setq region-pin-position 'top-right)  ; 'top-right (default), 'top-left, 'top-center
(setq region-pin-max-width 80) 
(setq region-pin-max-height 20)
(setq region-pin-margin 12)            ; gap in pixels from the window edge
(setq region-pin-header-icon "📌")     ; set to just "" to disable the icon
```
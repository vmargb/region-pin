# region-pin.el

<div align="center">
  <img src="region-pin-example.png" alt="region-pin demo" width="800"/>
  <p><em><code>region-pin</code> demo</em></p>
</div>

---

## The problem this solves:
You're editing code that uses a long struct, function (or any other chunk of code)
defined somewhere far away or in another file, and you keep
jumping back and forth to remember the field or arg names. `region-pin` lets you save
that snippet once under a name, then preview a syntax-highlighted
floating preview of it in the corner of your window. 

### Why not just split the window?

This was the design of *v0.1.0*, and it wasted space. A full-width split
ends up showing a huge blank margin of unused space next to the snippet you actually want.
Not to mention, when you already have a complicated window configuration set up,
adding one more gets even messier.

Instead, `region-pin` *floats* at the top of the frame regardless of your window configuration.

However, terminal Emacs doesn't support child frames, in this case it
automatically falls back to a window split docked to the top of the frame.

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
(global-set-key (kbd "C-c p i") #'region-pin-instant) ; instantly pin region (without a name)
(global-set-key (kbd "C-c p p") #'region-pin-save)    ; save region with a name
(global-set-key (kbd "C-c p s") #'region-pin-show)    ; show a saved/named region
(global-set-key (kbd "C-c p h") #'region-pin-hide)    ; hide any existing region pins
(global-set-key (kbd "C-c p n") #'region-pin-next)    ; go to next named region
(global-set-key (kbd "C-c p P") #'region-pin-previous); go to previous named region
(global-set-key (kbd "C-c p d") #'region-pin-delete)  ; delete a named region
```

## Customization

```elisp
(setq region-pin-position 'top-right)  ; 'top-right (default), 'top-left, 'top-center
(setq region-pin-max-width 80) 
(setq region-pin-max-height 20)
(setq region-pin-margin 12)            ; gap in pixels from the window edge
(setq region-pin-header-icon "📌")     ; set to just "" to disable the icon
```
# Mach overview
The Mach engine is organized into modules. A module consits of systems, components, and utility functions. The modules provided by Mach are:
* Core
* Audio
* gfx.Sprite
* gfx.SpritePipeline
* gfx.Text
* gfx.TextPipeline
* gfx.TextStyle

The Core module handles creating a window and running the game loop. It will interface with the App module that the user needs to provide for their game.

## Mach app
An App module needs to provide the following systems:
* init
* deinit
* tick

The name of the module needs to be .app. The Core module will schedule a tick for the App module until the .exit system is scheduled.

To render to the screen the App can get the current texture view from the swap chain from mach.core. It will then begin a render pass. When the render pass is finished it will submit the commands to the device queue. Finally, schedule the mach.Core .update and .present_frame systems.

# Mach Core
The mach.Core module manges the graphic backend, window, and input in a platform indpendent way. 
The sysgpu and Platform interfaces (API) are used to abstract away the platform dependencies.


## Systems
The systems provided by mach.Core are:
    * init (core_options) - scheduled by mach.App
    * present_frame - schedule by user when the current frame is ready to be presented.
    * exit - scheduled by the the user when the application should exit.
    * deinit - scheduled by mach.App

If the mach.App application loop is used then the user only needs to schedule present_frame and exit.

## Core options
    The following options can be provided when initializing mach.Core.

    * allocator
    * is_app
    * headless
    * display_mode
    * border
    * title
    * size
    * power_preference
    * required_features
    * required_limits
    * swap_chain_usage
        - render_attachment

## Components
    * title
    * framebuffer_format
    * framebuffer_width
    * framebuffer_height
    * width
    * height
    * fullscreen

The main window entity contains all of the components above.

## State
The mach.Core has the following state variables that can be accessed from .state()
    * allocator
    * main_window       - Entity ID for the main window
    * platform          - Access to the underlying platform backend (e.g Wayland, win32)
    * title             - Window title
    * should_close      - Used by mach.App to determine if the application should close
    * linux_gamemode
    * frame             - Frame frequency
    * Might be accessed from platform
        - input_frequency
        - swap_chain_updates
    * GPU
        - instance
        - adapter
        - device
        - queue
        - surface
        - swap_chain
        - descriptor

## Notes

mach.App.deinit should not take an allocator as a paremeter. It should always use the same used by init.

The window height and width are the size of the drawable region, excluding borders and other window decorators.

Use vec for position parameters. E.g. x,y or widht,height. 

High DPI is not supported


### Events
Focus lost / gained not reported
Resize not reported

### Mouse handling
Mouse event not received if cursor goes out of screen. Core should provide an option to "capture" the mouse.

### Keyboard handling
Prt Scr is not captured
Fn not captured
F7 is not reported

-- Decide which key combinations should be captured. E.g. override operating system specific ones, like Alt F4 in windows means close app.

# Notes 
Collection of comments and question regarding Mach.

* Position used for mouse position in MouseButtonEvent is a f64.


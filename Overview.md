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

# Notes 
Collection of comments and question regarding Mach.

* Position used for mouse position in MouseButtonEvent is a f64.


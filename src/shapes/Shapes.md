# Shapes module

The Shapes module provides utility functions for drawing basic shapes such as rectangles, circles, and lines.

## Components
* transformation
* rectangle
    * width
    * height
* circle
* line
* style
    * color



## Appendix
Example of how the Sprite module is setup. It consists of SpritePipeline and Sprite.

Typical flow is as follow:

app init
    create pipeline
    pipeline update

app tick
    update sprite transforms
    sprite.update
        update buffers

    set view transform
    pipeline.preRender
        Update state in pipeline, e.g. view_projection transform.

    pipeline.render
        activate pipeline
        bind buffers
        draw

app deinit
    sprite deinit
    pipeline deinit
Reads and decompresses a PCX image of any size. The same loader works both at compile-time and at run-time.

In order to make this work, the loader is split into two functions: `preload`, which reads the header information (including the image dimensions), and `loadIntoRGB`, which takes a prepared buffer and reads and decompresses the image into it. At runtime, you would use an allocator to create this buffer in between `preload` and `loadIntoRGB`; at compile-time, you can simply declare a static array using the image dimensions.

The loader works on any kind of `InStream`, and doesn't need to know the length of the input.

The loader is contained in `pcx.zig`.

There are two tests, which render an ASCII translation of the image.

```
zig test pcx_test_comptime.zig
zig test pcx_test_runtime.zig
```

Both should produce the following output (the comptime test writes it as a compile log message, the runtime test prints it as usual).

```
             *---*              
            *-  --*             
            ***@*@@             
            @*-@*@@             
        ****@@*** -*            
       **- **@@*-@@-            
       *- --**@@*@@*            
       *---*@**@@@@             
       @*-*@@@****%++-     ++   
       *- -*@@%%%@@%%@%++++++-  
        @@@@@@+++%+++-@@@@%++%  
        *--*@@++%@++++%%%%%%%%  
        *-*@@@%%@@@@%@@-*-      
       *---***@@-*--+@----      
       *--*----*---@@@****      
        *-*--**@--*@@@          
          @@@@@@@@@             
          *--*--*@*             
          @***--*@@             
         *---@**@@*             
         *---*@@@***            
         @@-** @@@*@@           
        --*@*   @@@**           
        ---*@   @@***           
        **-*@   @@@@@           
        --*@    @@@**           
       *--*@    @@**            
       *-*@     @@@*            
       @@*@     @@@@            
       --@@     @@@**           
      ---*@     @@@***          
      ****@     @@@@@@          
```

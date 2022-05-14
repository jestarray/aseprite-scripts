local json = {_version = "0.1.1"}

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t"
}

local escape_char_map_inv = {["\\/"] = "/"}
for k, v in pairs(escape_char_map) do escape_char_map_inv[v] = k end

local function escape_char(c)
    return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_nil(val) return "null" end

local function encode_table(val, stack)
    local res = {}
    stack = stack or {}

    -- Circular reference?
    if stack[val] then error("circular reference") end

    stack[val] = true

    if val[1] ~= nil or next(val) == nil then
        -- Treat as array -- check keys are valid and it is not sparse
        local n = 0
        for k in pairs(val) do
            if type(k) ~= "number" then
                error("invalid table: mixed or invalid key types")
            end
            n = n + 1
        end
        if n ~= #val then error("invalid table: sparse array") end
        -- Encode
        for i, v in ipairs(val) do table.insert(res, encode(v, stack)) end
        stack[val] = nil
        return "[" .. table.concat(res, ",") .. "]"

    else
        -- Treat as an object
        for k, v in pairs(val) do
            if type(k) ~= "string" then
                error("invalid table: mixed or invalid key types")
            end
            table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
        end
        stack[val] = nil
        return "{" .. table.concat(res, ",") .. "}"
    end
end

local function encode_string(val)
    return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_number(val)
    -- Check for NaN, -inf and inf
    if val ~= val or val <= -math.huge or val >= math.huge then
        error("unexpected number value '" .. tostring(val) .. "'")
    end
    return string.format("%.14g", val)
end

local type_func_map = {
    ["nil"] = encode_nil,
    ["table"] = encode_table,
    ["string"] = encode_string,
    ["number"] = encode_number,
    ["boolean"] = tostring
}

encode = function(val, stack)
    local t = type(val)
    local f = type_func_map[t]
    if f then return f(val, stack) end
    error("unexpected type '" .. t .. "'")
end

function json.encode(val) return (encode(val)) end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do res[select(i, ...)] = true end
    return res
end

local space_chars = create_set(" ", "\t", "\r", "\n")
local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals = create_set("true", "false", "null")

local literal_map = {["true"] = true, ["false"] = false, ["null"] = nil}

local function next_char(str, idx, set, negate)
    for i = idx, #str do if set[str:sub(i, i)] ~= negate then return i end end
    return #str + 1
end

local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
        col_count = col_count + 1
        if str:sub(i, i) == "\n" then
            line_count = line_count + 1
            col_count = 1
        end
    end
    error(string.format("%s at line %d col %d", msg, line_count, col_count))
end

local function codepoint_to_utf8(n)
    -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
    local f = math.floor
    if n <= 0x7f then
        return string.char(n)
    elseif n <= 0x7ff then
        return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then
        return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128,
                           n % 64 + 128)
    elseif n <= 0x10ffff then
        return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                           f(n % 4096 / 64) + 128, n % 64 + 128)
    end
    error(string.format("invalid unicode codepoint '%x'", n))
end

local function parse_unicode_escape(s)
    local n1 = tonumber(s:sub(3, 6), 16)
    local n2 = tonumber(s:sub(9, 12), 16)
    -- Surrogate pair?
    if n2 then
        return
            codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
        return codepoint_to_utf8(n1)
    end
end

local function parse_string(str, i)
    local has_unicode_escape = false
    local has_surrogate_escape = false
    local has_escape = false
    local last
    for j = i + 1, #str do
        local x = str:byte(j)

        if x < 32 then
            decode_error(str, j, "control character in string")
        end

        if last == 92 then -- "\\" (escape char)
            if x == 117 then -- "u" (unicode escape sequence)
                local hex = str:sub(j + 1, j + 5)
                if not hex:find("%x%x%x%x") then
                    decode_error(str, j, "invalid unicode escape in string")
                end
                if hex:find("^[dD][89aAbB]") then
                    has_surrogate_escape = true
                else
                    has_unicode_escape = true
                end
            else
                local c = string.char(x)
                if not escape_chars[c] then
                    decode_error(str, j,
                                 "invalid escape char '" .. c .. "' in string")
                end
                has_escape = true
            end
            last = nil

        elseif x == 34 then -- '"' (end of string)
            local s = str:sub(i + 1, j - 1)
            if has_surrogate_escape then
                s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
            end
            if has_unicode_escape then
                s = s:gsub("\\u....", parse_unicode_escape)
            end
            if has_escape then s = s:gsub("\\.", escape_char_map_inv) end
            return s, j + 1

        else
            last = x
        end
    end
    decode_error(str, i, "expected closing quote for string")
end

local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then decode_error(str, i, "invalid number '" .. s .. "'") end
    return n, x
end

local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
        decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
end

local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
        local x
        i = next_char(str, i, space_chars, true)
        -- Empty / end of array?
        if str:sub(i, i) == "]" then
            i = i + 1
            break
        end
        -- Read token
        x, i = parse(str, i)
        res[n] = x
        n = n + 1
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "]" then break end
        if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
end

local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
        local key, val
        i = next_char(str, i, space_chars, true)
        -- Empty / end of object?
        if str:sub(i, i) == "}" then
            i = i + 1
            break
        end
        -- Read key
        if str:sub(i, i) ~= '"' then
            decode_error(str, i, "expected string for key")
        end
        key, i = parse(str, i)
        -- Read ':' delimiter
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) ~= ":" then
            decode_error(str, i, "expected ':' after key")
        end
        i = next_char(str, i + 1, space_chars, true)
        -- Read value
        val, i = parse(str, i)
        -- Set
        res[key] = val
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "}" then break end
        if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
end

local char_func_map = {
    ['"'] = parse_string,
    ["0"] = parse_number,
    ["1"] = parse_number,
    ["2"] = parse_number,
    ["3"] = parse_number,
    ["4"] = parse_number,
    ["5"] = parse_number,
    ["6"] = parse_number,
    ["7"] = parse_number,
    ["8"] = parse_number,
    ["9"] = parse_number,
    ["-"] = parse_number,
    ["t"] = parse_literal,
    ["f"] = parse_literal,
    ["n"] = parse_literal,
    ["["] = parse_array,
    ["{"] = parse_object
}

parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then return f(str, idx) end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
end

function json.decode(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then decode_error(str, idx, "trailing garbage") end
    return res
end

--[[
    jest_import_packed_atlas
    Useful in case you lose your ASE file and only have the output .png & .json files
    This script IMPORTS packed sprites, e,g texture atlases, or exports from aseprite, back into their original form.
    Just open the png file up as the current tab, select the corresponding json and done. 
    !!WARNING: PROBABLY DOES NOT SUPPORT ROTATED TEXTURE ATLASES!!
    It will also import tags if they exist in the json file

    This script also has CLI support so you can mass convert your texture atlases:
    aseprite.exe <SPRITE.png> --script-param json="C:\SPRITE.json" --script jest_import_packed_atlas.lua --save-as <RES.ase> --batch

    Your .json file can be either in array form, e.g:

{"frames": [
    {
        "filename": "Green Flash"
        "frame": {"x":1,"y":1,"w":31,"h":301},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x":0,"y":0,"w":31,"h":301},
        "sourceSize": {"w":31,"h":301
    }
]}

or hash form:

{"frames": {
    "Green Flash":
    {
        "frame": {"x":1,"y":1,"w":31,"h":301},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x":0,"y":0,"w":31,"h":301},
        "sourceSize": {"w":31,"h":301}
}}}

    If you see all white colors, it means you didn't have the packed sprite selected as the current tab when running this script 

    Check out jest_import_existing_tags(https://github.com/jestarray/aseprite-scripts/blob/master/jest_import_existing_tags.lua) if your json file also has meta data animation tags
  Credits:
    json decoding by rxi - https://github.com/rxi/json.lua
    
    script by jest(https://github.com/jestarray/aseprite-scripts) - for aseprite versions > 1.2.10
    
    Public domain, do whatever you want
]]

-- start main

local function split(str, sep)
    local result = {}
    local regex = ("([^%s]+)"):format(sep)
    for each in str:gmatch(regex) do table.insert(result, each) end
    return result
end

-- Image, Image, Rect, Rect, palette
-- src and dest are image classes
local function draw_section(src_img, dest_img, src_rect, dest_rect, palette)
    local frame = src_rect
    local source = dest_rect
    for y = 0, frame.h - 1, 1 do
        for x = 0, frame.w - 1, 1 do
            local src_x = frame.x + x
            local src_y = frame.y + y
            local color_or_index = src_img:getPixel(src_x, src_y)
            local color;
            if src_img.colorMode == ColorMode.INDEXED then
                -- fixes greenish artifacts when importing from an indexed file: https://discord.com/channels/324979738533822464/324979738533822464/975147445564604416
                -- because indexed sprites have a special index as the transparent color: https://www.aseprite.org/docs/color-mode/#indexed
                if color_or_index ~= src_img.spec.transparentColor then
                    color = palette:getColor(color_or_index)
                else
                    color = Color {r = 0, g = 0, b = 0, a = 0}
                end
            else
                color = color_or_index
            end
            -- DEPENDS ON THE COLOR MODE, MAKE SURE ITS NOT INDEXED, if indexed, grab the index coolor from the pallete, otherwise it is the color
            local dest_x = source.x + x
            local dest_y = source.y + y
            dest_img:drawPixel(dest_x, dest_y, color)
        end
    end
end

-- takes in jsondata.frames
local function jhash_to_jarray(hash)
    local res = {}
    for key, obj in pairs(hash) do
        obj["filename"] = key
        table.insert(res, obj)
    end
    table.sort(res, function(a, b) return a.filename < b.filename end)
    return res
end

local function is_array(hash)
    local res = false
    for key, obj in pairs(hash) do
        if type(key) == "number" then
            res = true
            break
        end
    end
    return res
end

local dlg = Dialog()
dlg:file{
    id = "picker",
    label = "select animation data file(json)",
    title = "animimation tag importer",
    load = true,
    open = true,
    filename = "",
    filetypes = {"json"},
    onchange = function()
        local filepath = dlg.data.picker -- matches id name
        local f = io.open(filepath, "r+"):read('a')
        local jsondata = json.decode(f)

        if jsondata == nil then
            print("could not load file " .. filepath)
            print("check your json file for errors")

            return 1
        end

        local image = app.activeImage
        local sprite = app.activeSprite
        if not is_array(jsondata.frames) then
            -- convert it so we can use it as an array
            jsondata.frames = jhash_to_jarray(jsondata.frames)
        end

        local og_size = jsondata.frames[1].sourceSize
        local new_sprite = Sprite(og_size.w, og_size.h)
        new_sprite:setPalette(sprite.palettes[1])

        local frame = new_sprite.frames[1]
        for index, aframe in pairs(jsondata.frames) do
            local src_loc = aframe.frame
            local place_loc = aframe.spriteSourceSize
            local dest_img = new_sprite.cels[index].image
            frame = new_sprite:newFrame()
            draw_section(image, dest_img, src_loc, place_loc, sprite.palettes[1])
            if aframe.duration ~= nil then
                frame.previous.duration = aframe.duration / 1000
            end
        end
        -- # is the length operator, delete the extra empty frame
        new_sprite:deleteFrame(#new_sprite.frames)

        -- IMPORTING FRAME TAGS
        if jsondata.meta ~= nil and jsondata.meta.frameTags then
            for index, tag_data in pairs(jsondata.meta.frameTags) do
                local name = tag_data.name
                local from = tag_data.from + 1
                local to = tag_data.to + 1
                local direction = tag_data.direction

                -- seems like exporting tags does not export their colors so no way to import them until aseprite starts exporting color of a tag in the output json file 

                local new_tag = new_sprite:newTag(from, to)
                new_tag.name = name
                new_tag.aniDir = direction

            end
        end

        for index, frame_data in pairs(jsondata.frames) do
            if frame_data.duration then
                local duration = frame_data.duration

                local current_frame = app.activeFrame
                current_frame.duration = duration / 1000 -- duraction in the editor is in seconds, e.g 0.1
                app.command.GoToNextFrame()
            end
        end

        -- FIXES CEL BOUNDS FROM BEING INCORRECT https://github.com/aseprite/aseprite/issues/3206 
        app.command.CanvasSize {
            ui = false,
            left = 0,
            top = 0,
            right = 0,
            bottom = 0,
            trimOutside = true
        }
        dlg:close()
    end
}:show()

local M = {}

-- global variables
local sqlite3 = require("lsqlite3")
local width = vim.api.nvim_win_get_width(0)
local height = vim.api.nvim_win_get_height(0)
local snippets_info = {}
local snippets_content = {}
-- maps its index to line number in mappings window
local cached_mapp_win = {}
local cached = 0
local buffer = vim.api.nvim_create_buf(false, true)
local window = -1
local snippet_win = -1
local forbidden_mappings = {"mapping", "name", "description", "snippet"}
local path_db = "/root/.config/nvim/lua/snippets.db"

local function create_db()
    -- make specific path since otherwise it gets created in current dir
    local db = sqlite3.open(path_db)
    -- create snippets table iff doesn't exist yet
    -- NOTE: mapping primary key since we guarantee that mappings are unique
    db:exec(
        [[
	CREATE TABLE IF NOT EXISTS snippets (
	mapping TEXT PRIMARY KEY,
	name TEXT,
	description TEXT,
	snippet TEXT);]]
    )
    db:close()
end

local function load_from_db()
    -- load all mappings (rows) stored in db and sets up keymaps
    local db = sqlite3.open(path_db)
    -- * indicates I want to select all rows form snippets
    local query = db:prepare("SELECT * FROM snippets;")
    -- step through results
    for row in query:nrows() do
        vim.keymap.set("i", row.mapping, row.snippet)
        local info = row.mapping .. " | " .. row.name .. " | " .. row.description
        table.insert(snippets_info, info)
        -- split snippet at "\n" to get the lines since we cant store lua table
        -- in database we have to always get the lines for buf_set_lines by splitting
        local lines = {}
        for line in string.gmatch(row.snippet, "([^" .. "\n" .. "]+)") do
            table.insert(lines, line)
        end
        -- cache snippet lines in snippets_content table
        snippets_content[row.mapping] = lines
    end
    query:finalize()
    db:close()
end

local function store_in_db(mapping, name, description, snippet)
    -- inserts new mappings into database
    local db = sqlite3.open(path_db)
    -- compile query into statement
    local query = db:prepare([[INSERT INTO snippets(mapping,name,
				description,snippet)
				VALUES(?,?,?,?);]])
    -- binds values to each ? in VALUES()
    query:bind_values(mapping, name, description, snippet)
    -- try to execute query
    query:step()
    -- frees prepared query
    query:finalize()
    -- close connection to db
    db:close()
end

local function get_keymap_from_line()
    -- retrieves keymap from mappings window
    local curr_line = vim.api.nvim_get_current_line()
    -- extract mapping only if line not empty
    if curr_line ~= "" then
        return curr_line:sub(1, curr_line:find(" ") - 1)
    end
    return ""
end

local function draw_mappings_window(redraw)
    -- draw all cached mappings onto the buffer, after the mappings were
    -- drawn remove them from the table since we do not want to re-draw them
    -- cached tells set_lines from where to draw new mappings
    vim.api.nvim_buf_set_option(buffer, "modifiable", true)
    if redraw then
        -- clear buffer
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
    else -- cache mappings that were newly added
        for i, mapp in ipairs(snippets_info) do
            table.insert(cached_mapp_win, mapp)
        end
    end
    vim.api.nvim_buf_set_lines(buffer, cached, 999, false, snippets_info)
    cached = cached + #snippets_info
    snippets_info = {}
    vim.api.nvim_buf_set_option(buffer, "modifiable", false)
end

M.delete_snippet = function()
    -- uses unique column <mapping> to delete single row out of db
    -- also deletes entry from mappings window, mappings window must be open for that
    if vim.api.nvim_win_is_valid(window) then
        local mapping = get_keymap_from_line()
        -- mapping cant be empty
        if mapping ~= "" then
            -- unset keymapping
            vim.api.nvim_del_keymap("i", mapping)
            -- put quotes around mapping since in sqlite you need " " around condition
            mapping = '"' .. mapping .. '"'
            local db = sqlite3.open(path_db)
            local query = db:exec("DELETE FROM snippets WHERE mapping = " .. mapping .. ";")
            -- get current line num
            local line_num = vim.fn.line(".")
            -- delete mapping from mappings window cache
            table.remove(cached_mapp_win, line_num)
            -- update snippets_info, force to redraw mappings, reset cached
            snippets_info = cached_mapp_win
            cached = 0
            draw_mappings_window(true)
            db:close()
        end
    end
end

local function find_lhs(mapping)
    -- retrieves table with currently reserved keymaps that are assigned to insert mode
    -- and searches in the table for entry lhs where mapping is stored
    local imappings = vim.api.nvim_get_keymap("i")
    for i, tables in ipairs(imappings) do
        if tables.lhs == mapping then
            return true
        end
    end
    return false
end

local function build_snippet(snippet)
    -- loops over all fetched lines and puts them seperated by \n into one string
    local snippet_str = snippet[1]
    for i = 2, #snippet do
        snippet_str = snippet_str .. "\n" .. snippet[i]
    end
    return snippet_str
end

local function translate_mapping(mapping)
    --[[
	nvim for some reason transformes <C-f> = <C-F> when mapping with vim.keymap.set
	also other mappings share same issue where the typed mapping differs from mapping
	stored in nvims internal mapping table -> see :map, to adress this issue
	I had the idea to first create a throwaway buffer, then set the user mapping to that buffer
	in mode n, if you now execute :nmap on that buffer the transformed user mapping shows up
	in the table, now I can just extract it store it in "out" and now I can guarantee that
	the user mapping can be found in imappings if it was already stored there
	]]
    if mapping ~= "" then
        local throwaway_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_keymap(throwaway_buf, "n", mapping, "", {})
        vim.api.nvim_buf_call(
            throwaway_buf,
            function()
                out = vim.api.nvim_exec(":nmap", true)
            end
        )
        out = out:sub(5)
        out = out:sub(1, out:find(" ") - 1)
        return out
    end
    return ""
end

local function find_str(pattern, arr)
    -- dont allow "name, "n"ame, "name" to be matched ...
    pattern = pattern:gsub('"', "")
    for i, str in ipairs(arr) do
        if pattern == str then
            return true
        end
    end
    return false
end

local function prompt_user()
    -- prompts the user to input name, mapping and description
    -- if the mapping is already occupied or forbidden, ask user to enter different mapping
    local mapping = vim.fn.input("Enter keymapping for snippet (example: <C-x> = Ctrl + x):")
    mapping = translate_mapping(mapping)
    while mapping == "" or find_str(mapping, forbidden_mappings) or find_lhs(mapping) do
        mapping = vim.fn.input("Mapping already in-use, enter different mapping:")
        mapping = translate_mapping(mapping)
    end
    local name = vim.fn.input("Enter name for snippet:")
    -- calc max_char by taking width of floating window subtracting len of name, mapping and 2x " | "
    local max_char = math.floor(vim.api.nvim_win_get_width(0) * 0.6) - #name - #mapping - 6 - 1
    local desc = vim.fn.input("Enter short description (max " .. max_char .. " characters) for snippet:")
    if #desc >= max_char then
        -- if description too long, add ... at end
        desc = desc:sub(1, max_char - 3) .. "..."
    end
    -- simulate pressing i to enter insert mode and Esc to return to normal mode to clear cmd line
    local key = vim.api.nvim_replace_termcodes("i<ESC>", true, false, true)
    vim.api.nvim_feedkeys(key, "n", true)
    return mapping, name, desc
end

M.get_selection = function()
    -- get position of start and end of visual selection
    local start_pos = vim.fn.getpos("'<")[2]
    local end_pos = vim.fn.getpos("'>")[2]
    -- based on the lines get the words from the buffer (-1 since api uses 0-based lines)
    local snippet = vim.api.nvim_buf_get_lines(0, start_pos - 1, end_pos, false)
    -- snippet cannot be empty
    if #snippet == 0 then
        print("No snippet selected, please select snippet!")
    else
        local mapping, name, desc = prompt_user()
        local snippet_str = build_snippet(snippet)
        -- set mapping
        vim.keymap.set("i", mapping, snippet_str)
        table.insert(snippets_info, mapping .. " | " .. name .. " | " .. desc)
        snippets_content[mapping] = snippet
        store_in_db(mapping, name, desc, snippet_str)
    end
end

M.snippet_window = function()
    -- closes mappings window and opens window with snippet inside
    -- only open if mappings window is currently open and entry in line not empty
    local mapping = get_keymap_from_line()
    if vim.api.nvim_win_is_valid(window) and mapping ~= "" then
        vim.api.nvim_win_close(window, true)
        local snippet_buf = vim.api.nvim_create_buf(false, true)
        snippet_win =
            vim.api.nvim_open_win(
            snippet_buf,
            true,
            {
                relative = "win",
                row = height * 0.18,
                col = width * 0.18,
                width = math.floor(width * 0.6),
                height = math.floor(height * 0.6),
                border = {"/", "-", "\\", "|"},
                style = "minimal",
                title = "MagiSnipp",
                title_pos = "center"
            }
        )
        vim.api.nvim_set_hl(0, "FloatTitle", {fg = "#ff0000"})
        vim.api.nvim_set_hl(0, "FloatBorder", {fg = "#0000ff"})
        vim.api.nvim_buf_set_option(snippet_buf, "modifiable", true)
        -- draw cached snippet lines onto buf, we need lines since buf_set cant interpret "\n"
        vim.api.nvim_buf_set_lines(snippet_buf, 0, 999, false, snippets_content[mapping])
        vim.api.nvim_buf_set_option(snippet_buf, "modifiable", false)
        -- set b key to go back to entry window -> call open_window()
        vim.api.nvim_buf_set_keymap(snippet_buf, "n", "b", ":lua require'MagiSnipp'.open_mappings_window()<cr>", {})
    end
end

M.open_mappings_window = function()
    -- calc size of floating window in comparison to main window (60%)
    -- open window with buffer attached, make it focused and define some options for it
    -- if snippet_window open close it
    if vim.api.nvim_win_is_valid(snippet_win) then
        vim.api.nvim_win_close(snippet_win, true)
    end
    window =
        vim.api.nvim_open_win(
        buffer,
        true,
        {
            relative = "win",
            row = height * 0.18,
            col = width * 0.18,
            width = math.floor(width * 0.6),
            height = math.floor(height * 0.6),
            border = {"/", "-", "\\", "|"},
            style = "minimal",
            title = "MagiSnipp",
            title_pos = "center"
        }
    )
    -- set some highlights
    vim.api.nvim_win_set_option(window, "cursorline", true)
    vim.api.nvim_set_hl(0, "FloatTitle", {fg = "#ff0000"})
    vim.api.nvim_set_hl(0, "FloatBorder", {fg = "#0000ff"})
    draw_mappings_window(false)
end

local function setup()
    -- disable comment insertion after newline
    local formatoptions = vim.opt.formatoptions:get()
    formatoptions.r = false
    vim.opt.formatoptions = formatoptions
    -- sets buffer mapping <d> of floating window to call of delete_snippet() on current line
    vim.api.nvim_buf_set_keymap(buffer, "n", "d", ":lua require'MagiSnipp'.delete_snippet()<cr>", {})
    -- sets enter key to call snippet_window()
    vim.api.nvim_buf_set_keymap(buffer, "n", "<cr>", ":lua require'MagiSnipp'.snippet_window()<cr>", {})
    create_db()
    load_from_db()
end

setup()

return M

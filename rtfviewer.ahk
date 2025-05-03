#Requires AutoHotkey v2.0
#Include <WebView2>  ; Assumes WebView2.ahk is in your Lib folder
#Include <JSON>

/*
 * RTF Viewer with ES Modules in WebView2
 * 
 * This script demonstrates how to:
 * 1. Create a WebView2 control in AHK
 * 2. Load ES modules in WebView2
 * 3. Process RTF content using JavaScript
 * 4. Pass data between AHK and WebView2
 */

class RtfViewer {
    ; Properties
    gui := ""
    wvc := ""        ; WebView2 Controller
    wv := ""         ; CoreWebView2 instance
    rtfContent := "" ; Current RTF content
    
    ; Constructor
    __New() {
        ; Create GUI
        this.gui := Gui("+Resize", "RTF Viewer with ES Modules")
        this.gui.OnEvent("Size", this.Gui_Size.Bind(this))
        this.gui.OnEvent("Close", this.Gui_Close.Bind(this))
        
        ; Add controls
        this.gui.AddButton("w120 h30", "Open RTF File").OnEvent("Click", this.OpenRtfFile.Bind(this))
        this.gui.AddButton("x+10 w120 h30", "Convert to HTML").OnEvent("Click", this.ConvertToHtml.Bind(this))
        this.gui.AddButton("x+10 w120 h30", "Convert to Plain").OnEvent("Click", this.ConvertToPlain.Bind(this))
        
        ; Add WebView control
        this.wvControl := this.gui.AddText("xm y+10 w800 h600")
        
        ; Create and initialize WebView2
        this.InitWebView2()
        
        ; Show GUI
        this.gui.Show("w800 h700")
    }
    
    ; Initialize WebView2
    InitWebView2() {
        try {
            ; Create WebView2 controller asynchronously
            this.wvc := WebView2.CreateControllerAsync(this.wvControl.Hwnd).await2()
            this.wv := this.wvc.CoreWebView2
            
            ; Set up event handlers
            this.wv.add_WebMessageReceived(WebView2.Handler(this.WebMessageReceived.Bind(this)))
            
            ; Add host object for AHK-JavaScript communication
            this.hostObj := {
                openFile: this.OpenFile.Bind(this),
                saveFile: this.SaveFile.Bind(this),
                showMessage: MsgBox,
                rtfContent: ""
            }
            this.wv.AddHostObjectToScript("ahk", this.hostObj)
            
            ; Load the HTML/JS application
            this.LoadWebApp()
            
        } catch as err {
            MsgBox("Error initializing WebView2: " err.Message, "WebView2 Error", "Icon!")
            ExitApp
        }
    }
    
    ; Load the HTML/JS application into WebView2
    LoadWebApp() {
        ; Create a temporary directory for our web application
        this.appDir := A_Temp "\RTFViewerApp"
        if !DirExist(this.appDir)
            DirCreate(this.appDir)
        
        ; Create index.html
        html := '
        (
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>RTF Processor</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    margin: 0;
                    padding: 20px;
                    display: flex;
                    flex-direction: column;
                    height: 100vh;
                    box-sizing: border-box;
                    overflow: hidden;
                }
                #container {
                    display: flex;
                    flex: 1;
                    overflow: hidden;
                }
                .panel {
                    flex: 1;
                    border: 1px solid #ccc;
                    padding: 10px;
                    overflow: auto;
                    margin: 0 5px;
                }
                .panel h3 {
                    margin-top: 0;
                    padding-bottom: 5px;
                    border-bottom: 1px solid #eee;
                }
                #status {
                    padding: 10px;
                    margin-top: 10px;
                    background-color: #f5f5f5;
                    border: 1px solid #ddd;
                    border-radius: 3px;
                }
                .rtf-document p {
                    margin: 0 0 10px 0;
                }
            </style>
        </head>
        <body>
            <h2>RTF Processor with ES Modules</h2>
            <div id="container">
                <div class="panel">
                    <h3>RTF Source</h3>
                    <textarea id="rtf-content" style="width: 100%; height: 100%; resize: none;"></textarea>
                </div>
                <div class="panel">
                    <h3>Preview</h3>
                    <div id="preview"></div>
                </div>
            </div>
            <div id="status">Ready</div>
            
            <script type="module">
                // Import our RTF parser module
                import { 
                    parseRtfString, 
                    convertToHtml, 
                    convertToPlain, 
                    simpleRtfToPlain 
                } from "./rtf-parser.js";
                
                // Get UI elements
                const rtfInput = document.getElementById("rtf-content");
                const preview = document.getElementById("preview");
                const status = document.getElementById("status");
                
                // Initialize with RTF content from AHK if available
                window.addEventListener("DOMContentLoaded", async () => {
                    try {
                        // Get RTF content from AHK
                        const content = await chrome.webview.hostObjects.ahk.rtfContent;
                        if (content) {
                            rtfInput.value = content;
                            status.textContent = "RTF content loaded from AHK";
                        }
                    } catch (error) {
                        status.textContent = `Error: ${error.message}`;
                    }
                    
                    // Sync RTF content with AHK when changed
                    rtfInput.addEventListener("input", () => {
                        chrome.webview.postMessage({
                            type: "rtfContentChanged",
                            content: rtfInput.value
                        });
                    });
                });
                
                // Expose functions to global scope for WebView2 to call
                window.parseAndConvertToHtml = () => {
                    try {
                        const rtfContent = rtfInput.value;
                        if (!rtfContent) {
                            status.textContent = "No RTF content to convert";
                            return;
                        }
                        
                        // Parse RTF content
                        const doc = parseRtfString(rtfContent);
                        
                        // Convert to HTML
                        const html = convertToHtml(doc);
                        
                        // Update preview
                        preview.innerHTML = html;
                        
                        // Update status
                        status.textContent = "Converted to HTML successfully";
                        
                        // Notify AHK
                        chrome.webview.postMessage({
                            type: "conversionComplete",
                            format: "html"
                        });
                    } catch (error) {
                        console.error("Error converting to HTML:", error);
                        status.textContent = `Error: ${error.message}`;
                        
                        // Try fallback method for simple RTF
                        try {
                            const plainText = simpleRtfToPlain(rtfInput.value);
                            preview.textContent = plainText;
                            status.textContent = "Used fallback conversion method";
                        } catch (e) {
                            status.textContent = `Fallback failed: ${e.message}`;
                        }
                    }
                };
                
                window.parseAndConvertToPlain = () => {
                    try {
                        const rtfContent = rtfInput.value;
                        if (!rtfContent) {
                            status.textContent = "No RTF content to convert";
                            return;
                        }
                        
                        // Use the simple converter for plain text
                        const plainText = simpleRtfToPlain(rtfContent);
                        
                        // Update preview
                        preview.textContent = plainText;
                        
                        // Update status
                        status.textContent = "Converted to plain text successfully";
                        
                        // Notify AHK
                        chrome.webview.postMessage({
                            type: "conversionComplete",
                            format: "plain",
                            content: plainText
                        });
                    } catch (error) {
                        console.error("Error converting to plain text:", error);
                        status.textContent = `Error: ${error.message}`;
                    }
                };
            </script>
        </body>
        </html>
        )'
        
        ; Create the ES module
        FileOpen(this.appDir "\index.html", "w").Write(html)
        
        ; Copy the RTF parser module
        rtfParserModule := FileRead(A_ScriptDir "\rtf-parser.js")
        if (!rtfParserModule) {
            ; If the file doesn't exist, we need to generate it using the ES module code
            ; You would need to include the contents of the ES module here
            ; For now, we'll just use a placeholder
            rtfParserModule := this.GetRtfParserModuleCode()
        }
        FileOpen(this.appDir "\rtf-parser.js", "w").Write(rtfParserModule)
        
        ; Navigate to our local web app
        this.wv.Navigate("file:///" StrReplace(this.appDir, "\", "/") "/index.html")
    }
    
    ; Generate RTF parser module code if the file doesn't exist
    GetRtfParserModuleCode() {
        ; This is a placeholder - in a real app, you would include
        ; the ES module code from rtf-parser.js here
        return '
        (
        // RTF Parser ES Module (simplified version)
        
        /**
         * Parse RTF string into a document structure
         */
        export function parseRtfString(rtfString) {
            if (!rtfString || typeof rtfString !== "string") {
                throw new Error("Invalid RTF content");
            }
            
            // Check if content is RTF
            if (!rtfString.startsWith("{\\rtf")) {
                throw new Error("Not a valid RTF document");
            }
            
            // Simple parsing logic for demonstration
            return {
                content: [
                    {
                        type: "paragraph",
                        content: [
                            {
                                type: "text",
                                text: "Parsed RTF content would appear here",
                                format: { bold: false, italic: false }
                            }
                        ]
                    }
                ]
            };
        }
        
        /**
         * Convert parsed RTF document to HTML
         */
        export function convertToHtml(document) {
            let html = "<div class=\"rtf-document\">";
            
            document.content.forEach(paragraph => {
                html += "<p>";
                
                paragraph.content.forEach(item => {
                    if (item.type === "text") {
                        html += item.text;
                    }
                });
                
                html += "</p>";
            });
            
            html += "</div>";
            return html;
        }
        
        /**
         * Convert parsed RTF document to plain text
         */
        export function convertToPlain(document) {
            let text = "";
            
            document.content.forEach(paragraph => {
                paragraph.content.forEach(item => {
                    if (item.type === "text") {
                        text += item.text;
                    }
                });
                
                text += "\n\n";
            });
            
            return text.trim();
        }
        
        /**
         * Simple RTF to plain text converter (fallback method)
         */
        export function simpleRtfToPlain(rtf) {
            return rtf
                .replace(/\\\\par[d]?/g, "\n")
                .replace(/\\{|\\}|\\\\|{|}|\\[a-z0-9]+[ ]?|-?[0-9]+/g, "")
                .trim();
        }
    )'
    }
    
    ; Event Handlers
    
    Gui_Size(gui, minMax, width, height) {
        if (minMax = -1)  ; Window is minimized
            return
        
        ; Resize WebView control to fit the window
        this.wvControl.Move(,, width, height - 40)
        
        ; Update WebView layout
        if (this.wvc)
            this.wvc.Bounds := {left: 0, top: 40, right: width, bottom: height}
    }
    
    Gui_Close(*) {
        ExitApp
    }
    
    OpenRtfFile(*) {
        ; Open file dialog to select RTF file
        selectedFile := FileSelect(1, , "Open RTF File", "RTF Files (*.rtf)")
        if (selectedFile && FileExist(selectedFile)) {
            ; Read the file content
            this.rtfContent := FileRead(selectedFile)
            this.hostObj.rtfContent := this.rtfContent
            
            ; Update the WebView content
            this.wv.ExecuteScript("document.getElementById('rtf-content').value = '" StrReplace(this.rtfContent, "``", "\\``") ";")
        }
    }
    
    ConvertToHtml(*) {
        this.wv.ExecuteScript("window.parseAndConvertToHtml();")
    }
    
    ConvertToPlain(*) {
        this.wv.ExecuteScript("window.parseAndConvertToPlain();")
    }
    
    ; Communication handlers
    
    WebMessageReceived(handler, args) {
        ; Parse the message from WebView
        webview2args := WebView2.WebMessageReceivedEventArgs(args)
        message := webview2args.WebMessageAsJson
        
        ; Process message
        try {
            data := JSON.Parse(message)
            
            switch data.type {
                case "rtfContentChanged":
                    this.rtfContent := data.content
                    this.hostObj.rtfContent := this.rtfContent
                
                case "conversionComplete":
                    MsgBox("Conversion to " data.format " completed successfully!", "Conversion Complete", "Info")
                
                default:
                    ; Unknown message type
                    MsgBox("Received unknown message type: " data.type, "WebView2 Message", "Info")
            }
        } catch as err {
            MsgBox("Error processing message: " err.Message, "Error", "Icon!")
        }
    }
    
    ; File operations for JavaScript
    
    OpenFile(fileType := "rtf") {
        static fileTypes := {
            rtf: "RTF Files (*.rtf)",
            txt: "Text Files (*.txt)",
            html: "HTML Files (*.htm; *.html)"
        }
        
        filter := fileTypes.HasOwnProp(fileType) ? fileTypes[fileType] : "All Files (*.*)"
        selectedFile := FileSelect(1, , "Open File", filter)
        
        if (selectedFile && FileExist(selectedFile))
            return FileRead(selectedFile)
        return ""
    }
    
    SaveFile(content, fileType := "rtf") {
        static fileTypes := {
            rtf: "RTF Files (*.rtf)",
            txt: "Text Files (*.txt)",
            html: "HTML Files (*.htm; *.html)"
        }
        
        filter := fileTypes.HasOwnProp(fileType) ? fileTypes[fileType] : "All Files (*.*)"
        selectedFile := FileSelect(16, , "Save File", filter)
        
        if (selectedFile) {
            FileOpen(selectedFile, "w").Write(content)
            return true
        }
        return false
    }
}

; Create and start the application
app := RtfViewer()

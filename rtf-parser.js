// rtf-parser.js - ES Module for RTF Processing
// This module provides RTF parsing capabilities in ES module format

/**
 * RTF Parser Module
 * Converts Rich Text Format (RTF) content to HTML or plain text
 */

// -- Constants --

// RTF Control Words
const CONTROL_WORDS = {
  // Character formatting
  'b': { type: 'format', format: 'bold', on: true },
  'b0': { type: 'format', format: 'bold', on: false },
  'i': { type: 'format', format: 'italic', on: true },
  'i0': { type: 'format', format: 'italic', on: false },
  'ul': { type: 'format', format: 'underline', on: true },
  'ulnone': { type: 'format', format: 'underline', on: false },
  'strike': { type: 'format', format: 'strikethrough', on: true },
  'strike0': { type: 'format', format: 'strikethrough', on: false },
  
  // Paragraph formatting
  'par': { type: 'paragraph' },
  'pard': { type: 'reset', target: 'paragraph' },
  
  // Special characters
  'tab': { type: 'char', value: '\t' },
  'line': { type: 'char', value: '\n' },
  
  // Color and Font controls
  'cf': { type: 'color', target: 'foreground' },
  'cb': { type: 'color', target: 'background' },
  'f': { type: 'font' },
  'fs': { type: 'fontSize' },
  
  // RTF header controls
  'rtf': { type: 'header' },
  'ansi': { type: 'charset', charset: 'ansi' },
  'mac': { type: 'charset', charset: 'mac' },
  'pc': { type: 'charset', charset: 'pc' },
  'pca': { type: 'charset', charset: 'pca' },
  'ansicpg': { type: 'codepage' }
};

// -- Tokenizer --

/**
 * Tokenize RTF content into tokens
 * @param {string} rtfContent - The RTF content to tokenize
 * @return {Array} Array of tokens
 */
export function tokenizeRTF(rtfContent) {
  const tokens = [];
  let pos = 0;
  
  while (pos < rtfContent.length) {
    const char = rtfContent[pos];
    
    // Handle opening braces (group start)
    if (char === '{') {
      tokens.push({ type: 'GROUP_START' });
      pos++;
      continue;
    }
    
    // Handle closing braces (group end)
    if (char === '}') {
      tokens.push({ type: 'GROUP_END' });
      pos++;
      continue;
    }
    
    // Handle control words
    if (char === '\\') {
      // Skip the backslash
      pos++;
      
      // Handle escaped characters (\{, \}, \\)
      if (pos < rtfContent.length) {
        if (rtfContent[pos] === '{' || rtfContent[pos] === '}' || rtfContent[pos] === '\\') {
          tokens.push({ 
            type: 'TEXT', 
            text: rtfContent[pos] 
          });
          pos++;
          continue;
        }
        
        // Handle Unicode character \'XX
        if (rtfContent[pos] === '\'') {
          pos++; // Skip the quote
          
          if (pos + 1 < rtfContent.length) {
            const hex = rtfContent.substring(pos, pos + 2);
            try {
              const charCode = parseInt(hex, 16);
              tokens.push({ 
                type: 'TEXT', 
                text: String.fromCharCode(charCode) 
              });
              pos += 2;
            } catch(e) {
              // Invalid hex, just skip it
              pos += 2;
            }
            continue;
          }
        }
        
        // Parse control word
        let controlWord = '';
        let paramStr = '';
        let hasParam = false;
        
        // Get the control word (letters)
        while (pos < rtfContent.length && 
               /[a-zA-Z0-9]/.test(rtfContent[pos])) {
          controlWord += rtfContent[pos];
          pos++;
        }
        
        // Get the parameter (numbers)
        if (pos < rtfContent.length && rtfContent[pos] === '-') {
          paramStr += '-';
          pos++;
        }
        
        while (pos < rtfContent.length && 
               /[0-9]/.test(rtfContent[pos])) {
          paramStr += rtfContent[pos];
          pos++;
          hasParam = true;
        }
        
        // Skip the delimiter (space or other)
        if (pos < rtfContent.length && rtfContent[pos] === ' ') {
          pos++;
        }
        
        // Add the control word token
        tokens.push({
          type: 'CONTROL',
          word: controlWord,
          param: hasParam ? parseInt(paramStr, 10) : null
        });
        
        continue;
      }
    }
    
    // Handle regular text
    let text = '';
    while (pos < rtfContent.length && 
           rtfContent[pos] !== '{' && 
           rtfContent[pos] !== '}' && 
           rtfContent[pos] !== '\\') {
      text += rtfContent[pos];
      pos++;
    }
    
    if (text) {
      tokens.push({ type: 'TEXT', text });
    }
  }
  
  return tokens;
}

// -- Parser --

/**
 * Parse RTF tokens into a document structure
 * @param {Array} tokens - Array of RTF tokens
 * @return {Object} Document structure
 */
export function parseRTF(tokens) {
  const document = {
    metadata: {
      fonts: [],
      colors: [],
      charset: 'ansi',
      codepage: 1252
    },
    content: []
  };
  
  let formatStack = [{ bold: false, italic: false, underline: false, strikethrough: false }];
  let currentFormat = formatStack[0];
  let currentParagraph = { type: 'paragraph', content: [] };
  
  document.content.push(currentParagraph);
  
  // Process all tokens
  let i = 0;
  function processGroup() {
    const groupStack = []; // Stack to track nested groups
    
    while (i < tokens.length) {
      const token = tokens[i++];
      
      switch (token.type) {
        case 'GROUP_START':
          groupStack.push(true);
          formatStack.push({ ...currentFormat });
          currentFormat = formatStack[formatStack.length - 1];
          break;
          
        case 'GROUP_END':
          if (groupStack.length > 0) {
            groupStack.pop();
            formatStack.pop();
            currentFormat = formatStack[formatStack.length - 1];
          }
          
          if (groupStack.length === 0) {
            return; // End of the current group
          }
          break;
          
        case 'CONTROL':
          handleControlWord(token);
          break;
          
        case 'TEXT':
          if (token.text.trim()) {
            currentParagraph.content.push({
              type: 'text',
              text: token.text,
              format: { ...currentFormat }
            });
          }
          break;
      }
    }
  }
  
  function handleControlWord(token) {
    const { word, param } = token;
    
    // Check for control words with numeric suffixes like 'b0'
    let baseWord = word;
    let suffix = null;
    
    if (/^[a-z]+[0-9]+$/.test(word)) {
      // Extract the base word and numeric suffix
      const match = word.match(/^([a-z]+)([0-9]+)$/);
      if (match) {
        baseWord = match[1];
        suffix = parseInt(match[2], 10);
      }
    }
    
    // Handle based on control word
    if (baseWord === 'b') {
      currentFormat.bold = (suffix !== 0);
    } else if (baseWord === 'i') {
      currentFormat.italic = (suffix !== 0);
    } else if (baseWord === 'ul') {
      currentFormat.underline = true;
    } else if (word === 'ulnone') {
      currentFormat.underline = false;
    } else if (baseWord === 'strike') {
      currentFormat.strikethrough = (suffix !== 0);
    } else if (word === 'par' || word === 'line') {
      // New paragraph
      currentParagraph = { type: 'paragraph', content: [] };
      document.content.push(currentParagraph);
    } else if (word === 'pard') {
      // Reset paragraph formatting
      currentFormat = { bold: false, italic: false, underline: false, strikethrough: false };
    } else if (word === 'f' && param !== null) {
      // Font selection
      currentFormat.font = param;
    } else if (word === 'fs' && param !== null) {
      // Font size (in half-points)
      currentFormat.fontSize = param / 2;
    } else if (word === 'cf' && param !== null) {
      // Foreground color
      currentFormat.foregroundColor = param;
    } else if (word === 'cb' && param !== null) {
      // Background color
      currentFormat.backgroundColor = param;
    }
    // Additional control words can be handled here
  }
  
  // Start processing
  processGroup();
  
  // Remove empty paragraphs
  document.content = document.content.filter(para => 
    para.content && para.content.length > 0
  );
  
  return document;
}

/**
 * Convert an RTF string to a document structure
 * @param {string} rtfString - The RTF content
 * @return {Object} Document structure
 */
export function parseRtfString(rtfString) {
  if (!rtfString || typeof rtfString !== 'string') {
    throw new Error('Invalid RTF content');
  }
  
  // Check if content is RTF
  if (!rtfString.startsWith('{\\rtf')) {
    throw new Error('Not a valid RTF document');
  }
  
  const tokens = tokenizeRTF(rtfString);
  return parseRTF(tokens);
}

/**
 * Convert a parsed RTF document to HTML
 * @param {Object} document - Parsed RTF document
 * @return {string} HTML content
 */
export function convertToHtml(document) {
  if (!document || !document.content) {
    return '';
  }
  
  let html = '<div class="rtf-document">\n';
  
  document.content.forEach(paragraph => {
    html += '  <p>';
    
    paragraph.content.forEach(item => {
      if (item.type === 'text') {
        let text = escapeHtml(item.text);
        const format = item.format || {};
        
        // Apply formatting
        if (format.bold) text = `<strong>${text}</strong>`;
        if (format.italic) text = `<em>${text}</em>`;
        if (format.underline) text = `<u>${text}</u>`;
        if (format.strikethrough) text = `<s>${text}</s>`;
        
        // Apply font size if specified
        if (format.fontSize) {
          text = `<span style="font-size: ${format.fontSize}pt;">${text}</span>`;
        }
        
        html += text;
      }
    });
    
    html += '</p>\n';
  });
  
  html += '</div>';
  return html;
}

/**
 * Convert a parsed RTF document to plain text
 * @param {Object} document - Parsed RTF document
 * @return {string} Plain text content
 */
export function convertToPlain(document) {
  if (!document || !document.content) {
    return '';
  }
  
  let text = '';
  
  document.content.forEach(paragraph => {
    paragraph.content.forEach(item => {
      if (item.type === 'text') {
        text += item.text;
      }
    });
    
    text += '\n\n';
  });
  
  return text.trim();
}

/**
 * Simple RTF to plain text converter (fallback method)
 * @param {string} rtf - RTF content
 * @return {string} Plain text
 */
export function simpleRtfToPlain(rtf) {
  if (!rtf || typeof rtf !== 'string') {
    return '';
  }
  
  return rtf
    // Remove RTF commands
    .replace(/\{\*?\\[^{}]+}|[{}]|\\\n?[A-Za-z]+\n?(?:-?\d+)?[ ]?/g, '')
    // Remove hex escapes
    .replace(/\\'[0-9a-zA-Z]{2}/g, '')
    .trim();
}

/**
 * Escape HTML special characters
 * @param {string} text - Input text
 * @return {string} Escaped text
 */
function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Export all functions as named exports
export default {
  tokenizeRTF,
  parseRTF,
  parseRtfString,
  convertToHtml,
  convertToPlain,
  simpleRtfToPlain
};

/**
 * UI Components for Claude Session Manager
 * 
 * Reusable UI components using gum and fzf for terminal interfaces.
 * Provides consistent styling and interaction patterns.
 */

import { blue, bold, cyan, gray, green, red, yellow } from "https://deno.land/std@0.224.0/fmt/colors.ts";

/**
 * UI Component configuration
 */
export interface UIConfig {
  useColor: boolean;
  useEmoji: boolean;
  useGum: boolean;
  useFzf: boolean;
}

/**
 * Execute command helper
 */
async function exec(cmd: string, args: string[] = [], input?: string): Promise<string> {
  const command = new Deno.Command(cmd, {
    args,
    stdout: "piped",
    stderr: "piped",
    stdin: input ? "piped" : "null",
  });
  
  if (input) {
    const process = command.spawn();
    const writer = process.stdin!.getWriter();
    await writer.write(new TextEncoder().encode(input));
    await writer.close();
    const { stdout } = await process.output();
    return new TextDecoder().decode(stdout).trim();
  }
  
  const { stdout } = await command.output();
  return new TextDecoder().decode(stdout).trim();
}

/**
 * Check if command exists
 */
async function commandExists(cmd: string): Promise<boolean> {
  try {
    await exec("which", [cmd]);
    return true;
  } catch {
    return false;
  }
}

/**
 * Spinner component
 */
export class Spinner {
  private message: string;
  private frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  private current = 0;
  private intervalId: number | null = null;
  
  constructor(message: string) {
    this.message = message;
  }
  
  start(): void {
    this.intervalId = setInterval(() => {
      const frame = this.frames[this.current];
      Deno.stdout.writeSync(
        new TextEncoder().encode(`\r${cyan(frame)} ${this.message}`)
      );
      this.current = (this.current + 1) % this.frames.length;
    }, 80);
  }
  
  stop(finalMessage?: string): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    
    const msg = finalMessage || `✅ ${this.message}`;
    Deno.stdout.writeSync(
      new TextEncoder().encode(`\r${msg}${" ".repeat(20)}\n`)
    );
  }
}

/**
 * Progress bar component
 */
export class ProgressBar {
  private total: number;
  private current = 0;
  private width = 40;
  private label: string;
  
  constructor(total: number, label = "Progress") {
    this.total = total;
    this.label = label;
  }
  
  update(current: number, message?: string): void {
    this.current = Math.min(current, this.total);
    const percentage = Math.floor((this.current / this.total) * 100);
    const filled = Math.floor((this.current / this.total) * this.width);
    const empty = this.width - filled;
    
    const bar = `${"█".repeat(filled)}${"░".repeat(empty)}`;
    const status = message || `${this.current}/${this.total}`;
    
    Deno.stdout.writeSync(
      new TextEncoder().encode(
        `\r${this.label}: ${cyan(bar)} ${percentage}% - ${status}`
      )
    );
    
    if (this.current >= this.total) {
      Deno.stdout.writeSync(new TextEncoder().encode("\n"));
    }
  }
  
  complete(message?: string): void {
    this.update(this.total, message || "Complete!");
  }
}

/**
 * Selection menu using gum or fzf
 */
export class SelectionMenu<T> {
  private items: T[];
  private formatter: (item: T) => string;
  private config: UIConfig;
  
  constructor(
    items: T[],
    formatter: (item: T) => string,
    config?: Partial<UIConfig>
  ) {
    this.items = items;
    this.formatter = formatter;
    this.config = {
      useColor: config?.useColor ?? true,
      useEmoji: config?.useEmoji ?? true,
      useGum: config?.useGum ?? true,
      useFzf: config?.useFzf ?? false,
    };
  }
  
  async show(options: {
    title?: string;
    prompt?: string;
    preview?: boolean;
    multiSelect?: boolean;
  } = {}): Promise<T | T[] | null> {
    if (this.items.length === 0) {
      console.log(yellow("No items to select"));
      return null;
    }
    
    // Check available tools
    const hasGum = this.config.useGum && await commandExists("gum");
    const hasFzf = this.config.useFzf && await commandExists("fzf");
    
    if (hasGum && !this.config.useFzf) {
      return this.showWithGum(options);
    } else if (hasFzf) {
      return this.showWithFzf(options);
    } else {
      return this.showFallback(options);
    }
  }
  
  private async showWithGum(options: {
    title?: string;
    prompt?: string;
    multiSelect?: boolean;
  }): Promise<T | T[] | null> {
    const lines = this.items.map(this.formatter);
    const args = ["choose"];
    
    if (options.title) {
      args.push("--header", options.title);
    }
    
    if (options.multiSelect) {
      args.push("--no-limit");
    }
    
    args.push(...lines);
    
    const result = await exec("gum", args);
    
    if (!result) return null;
    
    if (options.multiSelect) {
      const selected = result.split("\n");
      return this.items.filter(item => 
        selected.includes(this.formatter(item))
      );
    } else {
      const index = lines.indexOf(result);
      return index >= 0 ? this.items[index] : null;
    }
  }
  
  private async showWithFzf(options: {
    title?: string;
    prompt?: string;
    preview?: boolean;
    multiSelect?: boolean;
  }): Promise<T | T[] | null> {
    const lines = this.items.map(this.formatter).join("\n");
    const args: string[] = [
      "--ansi",
      "--no-sort",
      "--layout=reverse",
    ];
    
    if (options.title) {
      args.push("--header", options.title);
    }
    
    if (options.prompt) {
      args.push("--prompt", options.prompt);
    }
    
    if (options.multiSelect) {
      args.push("--multi");
    }
    
    const result = await exec("fzf", args, lines);
    
    if (!result) return null;
    
    if (options.multiSelect) {
      const selected = result.split("\n");
      return this.items.filter(item => 
        selected.includes(this.formatter(item))
      );
    } else {
      const index = this.items.map(this.formatter).indexOf(result);
      return index >= 0 ? this.items[index] : null;
    }
  }
  
  private async showFallback(options: {
    title?: string;
    prompt?: string;
    multiSelect?: boolean;
  }): Promise<T | T[] | null> {
    if (options.title) {
      console.log(bold(blue(options.title)));
      console.log();
    }
    
    // Display items with numbers
    this.items.forEach((item, index) => {
      console.log(`${cyan(`[${index + 1}]`)} ${this.formatter(item)}`);
    });
    
    console.log();
    const promptText = options.prompt || "Select an option (number): ";
    const input = prompt(promptText);
    
    if (!input) return null;
    
    if (options.multiSelect) {
      const indices = input.split(",").map(s => parseInt(s.trim()) - 1);
      return indices
        .filter(i => i >= 0 && i < this.items.length)
        .map(i => this.items[i]);
    } else {
      const index = parseInt(input) - 1;
      return index >= 0 && index < this.items.length 
        ? this.items[index] 
        : null;
    }
  }
}

/**
 * Confirmation dialog
 */
export async function confirm(
  message: string,
  defaultValue = false
): Promise<boolean> {
  const hasGum = await commandExists("gum");
  
  if (hasGum) {
    try {
      await exec("gum", ["confirm", message]);
      return true;
    } catch {
      return false;
    }
  }
  
  // Fallback to built-in confirm
  const answer = prompt(`${message} (${defaultValue ? "Y/n" : "y/N"}): `);
  
  if (!answer) return defaultValue;
  
  const normalized = answer.toLowerCase().trim();
  return normalized === "y" || normalized === "yes";
}

/**
 * Input prompt
 */
export async function input(
  message: string,
  options: {
    placeholder?: string;
    defaultValue?: string;
    password?: boolean;
  } = {}
): Promise<string | null> {
  const hasGum = await commandExists("gum");
  
  if (hasGum) {
    const args = ["input"];
    
    if (options.placeholder) {
      args.push("--placeholder", options.placeholder);
    }
    
    if (options.defaultValue) {
      args.push("--value", options.defaultValue);
    }
    
    if (options.password) {
      args.push("--password");
    }
    
    args.push("--prompt", `${message} `);
    
    const result = await exec("gum", args);
    return result || null;
  }
  
  // Fallback to built-in prompt
  const result = prompt(message, options.defaultValue);
  return result || null;
}

/**
 * Text editor
 */
export async function editText(
  initialText = "",
  options: {
    title?: string;
    extension?: string;
  } = {}
): Promise<string | null> {
  const hasGum = await commandExists("gum");
  
  if (hasGum) {
    const args = ["write"];
    
    if (options.title) {
      args.push("--header", options.title);
    }
    
    if (initialText) {
      args.push("--value", initialText);
    }
    
    const result = await exec("gum", args);
    return result || null;
  }
  
  // Fallback: create temp file and open in editor
  const editor = Deno.env.get("EDITOR") || "nano";
  const tempFile = await Deno.makeTempFile({
    suffix: options.extension || ".txt",
  });
  
  if (initialText) {
    await Deno.writeTextFile(tempFile, initialText);
  }
  
  const command = new Deno.Command(editor, {
    args: [tempFile],
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  
  const { code } = await command.output();
  
  if (code === 0) {
    const content = await Deno.readTextFile(tempFile);
    await Deno.remove(tempFile);
    return content;
  }
  
  await Deno.remove(tempFile);
  return null;
}

/**
 * Display formatted table
 */
export function table(
  headers: string[],
  rows: string[][],
  options: {
    border?: boolean;
    color?: boolean;
  } = {}
): void {
  // Calculate column widths
  const widths = headers.map((h, i) => {
    const columnValues = [h, ...rows.map(r => r[i] || "")];
    return Math.max(...columnValues.map(v => v.length));
  });
  
  // Format header
  const headerRow = headers.map((h, i) => 
    h.padEnd(widths[i])
  ).join(" │ ");
  
  if (options.color !== false) {
    console.log(bold(cyan(headerRow)));
  } else {
    console.log(headerRow);
  }
  
  // Separator
  const separator = widths.map(w => "─".repeat(w)).join("─┼─");
  console.log(gray(separator));
  
  // Format rows
  rows.forEach(row => {
    const formattedRow = row.map((cell, i) => 
      (cell || "").padEnd(widths[i])
    ).join(" │ ");
    console.log(formattedRow);
  });
}

/**
 * Display styled box
 */
export function box(
  content: string | string[],
  options: {
    title?: string;
    border?: "single" | "double" | "rounded";
    padding?: number;
    color?: string;
  } = {}
): void {
  const lines = Array.isArray(content) ? content : content.split("\n");
  const padding = options.padding || 1;
  const maxWidth = Math.max(...lines.map(l => l.length));
  
  // Border characters
  const borders = {
    single: { tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│" },
    double: { tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║" },
    rounded: { tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│" },
  };
  
  const b = borders[options.border || "single"];
  
  // Top border
  let topBorder = b.tl + b.h.repeat(maxWidth + padding * 2) + b.tr;
  if (options.title) {
    const titleStr = ` ${options.title} `;
    const insertPos = Math.floor((topBorder.length - titleStr.length) / 2);
    topBorder = 
      topBorder.slice(0, insertPos) + 
      titleStr + 
      topBorder.slice(insertPos + titleStr.length);
  }
  
  console.log(options.color ? cyan(topBorder) : topBorder);
  
  // Content with padding
  lines.forEach(line => {
    const paddedLine = 
      " ".repeat(padding) + 
      line.padEnd(maxWidth) + 
      " ".repeat(padding);
    const row = `${b.v}${paddedLine}${b.v}`;
    console.log(options.color ? cyan(row) : row);
  });
  
  // Bottom border
  const bottomBorder = b.bl + b.h.repeat(maxWidth + padding * 2) + b.br;
  console.log(options.color ? cyan(bottomBorder) : bottomBorder);
}

/**
 * Display status message
 */
export function status(
  message: string,
  type: "success" | "error" | "warning" | "info" = "info"
): void {
  const icons = {
    success: "✅",
    error: "❌",
    warning: "⚠️",
    info: "ℹ️",
  };
  
  const colors = {
    success: green,
    error: red,
    warning: yellow,
    info: blue,
  };
  
  const icon = icons[type];
  const color = colors[type];
  
  console.log(`${icon} ${color(message)}`);
}
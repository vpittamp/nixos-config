# Research Documentation Index - Feature 034

**Feature**: Unified Application Launcher with Project Context
**Research Topics**:
1. Secure Variable Substitution for Application Launch Commands
2. Deno Compilation and NixOS Packaging
**Date**: 2025-10-24

---

## Document Overview

This research produced **7 comprehensive documents** covering secure variable substitution patterns, security risks, implementation examples, Deno packaging, and quick references.

---

## 📚 Documents by Purpose

### For Immediate Implementation (Read First)

0. **`QUICK_ANSWERS.md`** ⭐⭐⭐ **START HERE - 5 MIN READ**
   - Direct answers to the 5 research questions
   - deno compile command with recommended flags
   - Permission flags justification
   - Integration pattern with i3pm CLI
   - Build time estimates
   - **Length**: ~400 lines
   - **Read time**: 5 minutes
   - **Use when**: You want quick answers without deep research

### For Implementation (Read Second)

1. **`RESEARCH_SUMMARY.md`** ⭐ **START HERE**
   - Executive summary of all research findings
   - Recommended implementation approach (Tier 2)
   - Security threat model
   - Success criteria mapping
   - **Length**: ~350 lines
   - **Read time**: 10-15 minutes
   - **Use when**: You need to understand the overall approach

2. **`SECURITY_CHEATSHEET.md`** ⭐ **KEEP OPEN WHILE CODING**
   - Quick reference patterns (safe vs unsafe)
   - Common mistakes and how to avoid them
   - Validation patterns (copy-paste ready)
   - Testing checklist
   - **Length**: ~200 lines
   - **Read time**: 5 minutes
   - **Use when**: You're writing code and need quick examples

3. **`secure-substitution-examples.md`** ⭐ **COPY CODE FROM HERE**
   - Complete wrapper script implementation
   - Full test suite with all edge cases
   - Deno validation command implementation
   - home-manager module example
   - **Length**: ~600 lines
   - **Read time**: 20 minutes
   - **Use when**: You need complete working code examples

### For Deno/NixOS Packaging (Read Third)

6. **`DENO_PACKAGING_RESEARCH.md`** 📖 **DENO PACKAGING GUIDE**
   - Comprehensive Deno compilation and NixOS packaging research
   - Existing Deno package patterns in codebase (i3pm, cli-ux)
   - Runtime wrapper vs compiled binary comparison
   - Permission flags with security justification
   - Integration patterns with existing i3pm CLI
   - Build time analysis and recommendations
   - **Length**: ~850 lines
   - **Read time**: 30-40 minutes
   - **Use when**: You need to understand Deno packaging for NixOS

### For Deep Understanding (Read Fourth)

4. **`research-variable-substitution.md`** 📖 **COMPREHENSIVE REFERENCE**
   - Full research findings with citations
   - 11 detailed sections covering all aspects
   - Security analysis with attack scenarios
   - .desktop file specification details
   - Comparison with other launcher systems
   - **Length**: ~850 lines
   - **Read time**: 40-60 minutes
   - **Use when**: You need to understand **why** we made specific decisions

5. **`research-findings.md`** 📖 **ORIGINAL RESEARCH NOTES**
   - Initial research on rofi vs fzf, launcher patterns, daemon API
   - Decision rationales for launcher choice
   - Integration patterns with existing systems
   - **Length**: ~550 lines (pre-existing from Phase 0)
   - **Use when**: You need context on broader launcher design decisions

---

## 🎯 Reading Paths by Role

### Path 0: Quick Implementation (Just Get Started)

**Goal**: Start coding immediately with minimal reading

1. Read: `QUICK_ANSWERS.md` (5 min) ⭐
   - Get immediate answers to all questions
   - Understand recommended approach

2. Copy: `DENO_PACKAGING_RESEARCH.md` → Section 7 (5 min)
   - Copy derivation example
   - Copy TypeScript template

3. Reference: `SECURITY_CHEATSHEET.md` (as needed)
   - Look up validation patterns while coding

**Total time**: ~10 minutes reading + implementation time

---

### Path 1: Developer (Implementing the Feature)

**Goal**: Understand approach, write secure code

1. Read: `QUICK_ANSWERS.md` (5 min) ⭐
   - Get overview of Deno packaging approach
   - Understand integration pattern

2. Read: `RESEARCH_SUMMARY.md` (10 min)
   - Get overview of Tier 2 variable substitution
   - Understand security requirements

3. Read: `SECURITY_CHEATSHEET.md` (5 min)
   - Review safe patterns
   - Bookmark for reference

4. Copy: `secure-substitution-examples.md`
   - Use wrapper script template
   - Implement validation functions
   - Copy test suite

5. Copy: `DENO_PACKAGING_RESEARCH.md` → Section 7
   - Use derivation example
   - Use TypeScript command template

6. Reference: `research-variable-substitution.md` (as needed)
   - Look up specific topics (e.g., "How to escape dollar signs?")
   - Understand edge cases

**Total time**: ~25 minutes reading + implementation time

---

### Path 2: Security Reviewer

**Goal**: Verify implementation is secure

1. Read: `RESEARCH_SUMMARY.md` → Section "Security Threat Model"
   - Understand what's prevented vs. not prevented
   - Review validation rules

2. Read: `research-variable-substitution.md` → Section 2 "Command Injection Risks"
   - Review attack scenarios
   - Verify all mitigations implemented

3. Review: `secure-substitution-examples.md` → Wrapper Script
   - Check validation functions exist
   - Verify no `eval` or `sh -c` usage
   - Confirm argument array execution

4. Run: Test suite from `secure-substitution-examples.md`
   - All injection attempts rejected
   - Edge cases handled correctly

**Total time**: ~30 minutes

---

### Path 3: Architect / Decision Maker

**Goal**: Understand design rationale, approve approach

1. Read: `RESEARCH_SUMMARY.md` → Section "Decision Record"
   - Why Tier 2 (not Tier 1 or Tier 3)?
   - Why Bash wrapper (not Deno)?
   - Why home-manager for desktop files?

2. Read: `research-variable-substitution.md` → Section 1, 2, 9
   - Security analysis (Section 2)
   - Best practices from other systems (Section 9)
   - Final recommendations (Section 10)

3. Review: `RESEARCH_SUMMARY.md` → Success Criteria
   - Verify all spec requirements met

**Total time**: ~25 minutes

---

### Path 4: Future Maintainer

**Goal**: Understand why code is written this way

1. Read: `RESEARCH_SUMMARY.md` (full document)
   - Complete overview

2. Read: `research-variable-substitution.md` → Sections 2, 3, 4
   - Section 2: Why this is a security risk
   - Section 3: Edge cases to handle
   - Section 4: How wrapper script works

3. Reference: `SECURITY_CHEATSHEET.md`
   - Quick patterns for common modifications

**Total time**: ~40 minutes

---

## 📑 Document Sections Reference

### RESEARCH_SUMMARY.md Sections

1. TL;DR - Critical Findings
2. Recommended Implementation
3. Implementation Deliverables
4. Allowed Variables
5. Registry Parameter Examples
6. Validation Rules Summary
7. Security Threat Model
8. Comparison with Other Systems
9. Migration Strategy
10. Decision Record
11. Success Criteria

### research-variable-substitution.md Sections

1. Bash Parameter Expansion - Security Analysis
2. Command Injection Risks & Prevention
3. Special Character Handling & Edge Cases
4. Secure Substitution Pattern (Recommended Implementation)
5. Best Practices from .desktop File Specification
6. Validation Rules for Registry Entries
7. Testing Strategy & Test Cases
8. Implementation Recommendations (Tiers 1-3)
9. Comparison with Other Launcher Systems
10. Final Recommendations
11. References
12. Appendices (Wrapper Script, Test Matrix)

### secure-substitution-examples.md Sections

1. Quick Reference: Safe vs Unsafe Patterns
2. Wrapper Script Implementation Template
3. Desktop File Generation Pattern
4. Variable Substitution Test Cases
5. CLI Validation Command
6. Quick Decision Matrix
7. Checklist for Implementation

### SECURITY_CHEATSHEET.md Sections

1. The Golden Rule
2. Quick Patterns (Safe vs Unsafe)
3. Special Characters
4. Validation Patterns
5. Desktop File Pattern
6. Wrapper Script Template
7. Common Mistakes
8. Testing Checklist
9. Decision Tree
10. Key Takeaways

---

## 🔍 Topic Index (Find by Question)

### "How do I prevent command injection?"

- **`SECURITY_CHEATSHEET.md`** → Section "Quick Patterns"
- **`research-variable-substitution.md`** → Section 2 "Command Injection Risks"

### "What's the recommended implementation pattern?"

- **`RESEARCH_SUMMARY.md`** → Section "Recommended Implementation"
- **`secure-substitution-examples.md`** → Section "Wrapper Script Implementation"

### "How do I validate project directories?"

- **`SECURITY_CHEATSHEET.md`** → Section "Validation Patterns"
- **`secure-substitution-examples.md`** → Line ~50 (validate_directory function)

### "What variables are allowed?"

- **`RESEARCH_SUMMARY.md`** → Section "Allowed Variables"
- **`research-variable-substitution.md`** → Section 6 "Validation Rules"

### "How do I test for security issues?"

- **`secure-substitution-examples.md`** → Section "Variable Substitution Test Cases"
- **`SECURITY_CHEATSHEET.md`** → Section "Testing Checklist"

### "How do I package a Deno CLI tool for NixOS?"

- **`QUICK_ANSWERS.md`** → Section 3 "NixOS Derivation Patterns"
- **`DENO_PACKAGING_RESEARCH.md`** → Section 3 "NixOS Derivation Patterns for Deno"

### "Should I use deno compile or runtime wrapper?"

- **`QUICK_ANSWERS.md`** → TL;DR section
- **`DENO_PACKAGING_RESEARCH.md`** → Section 9 "Final Recommendations"

### "What permissions does the CLI need?"

- **`QUICK_ANSWERS.md`** → Section 4 "Permission Flags Justification"
- **`DENO_PACKAGING_RESEARCH.md`** → Section 4 "Permission Flags for i3pm Daemon Communication"

### "How do I integrate with the existing i3pm CLI?"

- **`QUICK_ANSWERS.md`** → Section 5 "Integration with i3pm CLI Structure"
- **`DENO_PACKAGING_RESEARCH.md`** → Section 5 "Integration with i3pm CLI Structure"

### "Why did we choose this approach?"

- **`RESEARCH_SUMMARY.md`** → Section "Decision Record"
- **`research-variable-substitution.md`** → Section 8 "Implementation Recommendations"

### "How do desktop files work with variables?"

- **`research-variable-substitution.md`** → Section 5 "Best Practices from .desktop File Specification"
- **`SECURITY_CHEATSHEET.md`** → Section "Desktop File Pattern"

### "What special characters need handling?"

- **`SECURITY_CHEATSHEET.md`** → Section "Special Characters That Break Unquoted Variables"
- **`research-variable-substitution.md`** → Section 3 "Special Character Handling"

### "How do other systems handle this?"

- **`research-variable-substitution.md`** → Section 9 "Comparison with Other Launcher Systems"

---

## 🚀 Implementation Workflow

### Step 1: Understand Approach (30 min)

- [ ] Read `RESEARCH_SUMMARY.md` in full
- [ ] Review `SECURITY_CHEATSHEET.md` for patterns
- [ ] Bookmark both documents

### Step 2: Implement Wrapper Script (2 hours)

- [ ] Copy template from `secure-substitution-examples.md`
- [ ] Implement `validate_directory()` function
- [ ] Implement `validate_parameters()` function
- [ ] Add variable substitution logic
- [ ] Add logging and error messages
- [ ] Test with `SECURITY_CHEATSHEET.md` checklist

### Step 3: Implement Validation (1 hour)

- [ ] Copy Deno CLI code from `secure-substitution-examples.md`
- [ ] Implement JSON schema validation
- [ ] Add parameter validation regex
- [ ] Test with malicious registry entries

### Step 4: Implement Desktop File Generation (1 hour)

- [ ] Create home-manager module
- [ ] Use pattern from `secure-substitution-examples.md`
- [ ] Test desktop file generation
- [ ] Verify launcher shows applications

### Step 5: Test Security (1 hour)

- [ ] Copy test suite from `secure-substitution-examples.md`
- [ ] Run all test cases
- [ ] Verify all injection attempts rejected
- [ ] Test with real projects containing spaces

### Step 6: Documentation (30 min)

- [ ] Create quickstart guide
- [ ] Update CLAUDE.md with launcher commands
- [ ] Document migration from old scripts

**Total estimated time**: ~6 hours

---

## 📊 Research Statistics

- **Total lines of research**: ~4,300 lines
- **Code examples**: 60+ complete code snippets
- **Test cases**: 12 edge cases with validation
- **External references**: 15+ sources (freedesktop, OWASP, bash docs, Deno manual, NixOS wiki)
- **Documents produced**: 7 (quick answers, summary, cheatsheet, examples, research, findings, Deno packaging)
- **Topics covered**: Variable substitution security, Deno compilation, NixOS packaging, IPC integration

---

## ✅ Pre-Implementation Checklist

Before starting implementation, verify you understand:

- [ ] Why we're using Tier 2 (restricted substitution)
- [ ] Why argument arrays are safer than string concatenation
- [ ] What variables are allowed and why they're whitelisted
- [ ] How to validate project directories securely
- [ ] What shell metacharacters must be blocked
- [ ] How the wrapper script execution flow works
- [ ] Why desktop files can't have inline variables
- [ ] How to test for command injection vulnerabilities

If you answered NO to any, re-read the relevant sections before implementing.

---

## 🔗 External References

All external research sources are documented in:
- **`research-variable-substitution.md`** → Section 11 "References"

Key external docs:
- [freedesktop.org Desktop Entry Spec](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- [GNU Bash Manual - Parameter Expansion](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html)
- [OWASP Command Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/OS_Command_Injection_Defense_Cheat_Sheet.html)

---

## 💡 Quick Navigation

**Need to find a specific topic?**

1. **Use Ctrl+F (Find)** in your editor to search across all documents
2. **Common search terms**:
   - "command injection" → Security analysis
   - "validate" → Validation patterns
   - "argument array" → Safe execution patterns
   - "desktop file" → Desktop file generation
   - "test case" → Test suite
   - "eval" → What NOT to do
   - "ARGS[@]" → Recommended execution pattern

**Still can't find it?**

- Check the **Topic Index** section above (organized by question)
- Read the full **Section Reference** for each document

---

**Last Updated**: 2025-10-24
**Feature Branch**: `034-create-a-feature`
**Related Phase**: Phase 0 Research (Complete)
**Next Phase**: Phase 1 Design (Data Model & Contracts)

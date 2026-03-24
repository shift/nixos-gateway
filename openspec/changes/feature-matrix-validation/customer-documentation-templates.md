# Customer-Facing Documentation Templates

## Support Matrix Web Dashboard

### HTML Template Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NixOS Gateway Support Matrix</title>
    <link rel="stylesheet" href="styles.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <header>
        <h1>NixOS Gateway Support Matrix</h1>
        <div class="metadata">
            <span class="version">Version: <strong>{{metadata.version}}</strong></span>
            <span class="updated">Last Updated: <strong>{{metadata.lastUpdated | date:'medium'}}</strong></span>
            <span class="framework">Framework: <strong>{{metadata.frameworkVersion}}</strong></span>
        </div>
    </header>

    <nav>
        <ul>
            <li><a href="#overview">Overview</a></li>
            <li><a href="#capabilities">Capabilities</a></li>
            <li><a href="#combinations">Supported Combinations</a></li>
            <li><a href="#compatibility">Compatibility Matrix</a></li>
            <li><a href="#examples">Configuration Examples</a></li>
        </ul>
    </nav>

    <main>
        <section id="overview">
            <h2>Support Overview</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <h3>{{metadata.totalCombinations}}</h3>
                    <p>Total Combinations Tested</p>
                </div>
                <div class="stat-card supported">
                    <h3>{{metadata.supportedCombinations}}</h3>
                    <p>Fully Supported</p>
                </div>
                <div class="stat-card conditional">
                    <h3>{{metadata.conditionallySupported}}</h3>
                    <p>Conditionally Supported</p>
                </div>
                <div class="stat-card unsupported">
                    <h3>{{metadata.notSupported}}</h3>
                    <p>Not Supported</p>
                </div>
            </div>

            <div class="support-levels">
                <h3>Support Level Definitions</h3>
                <div class="level-card fully-supported">
                    <h4>✅ Fully Supported</h4>
                    <p>Thoroughly tested, production-ready, full customer support available</p>
                </div>
                <div class="level-card conditional">
                    <h4>⚠️ Conditionally Supported</h4>
                    <p>Works with specific configurations or limitations, support available with conditions</p>
                </div>
                <div class="level-card unsupported">
                    <h4>❌ Not Supported</h4>
                    <p>Not tested or known compatibility issues, support not available</p>
                </div>
            </div>
        </section>

        <section id="capabilities">
            <h2>Available Capabilities</h2>
            <div class="capabilities-grid">
                {{#each capabilities}}
                <div class="capability-card" data-category="{{category}}">
                    <h3>{{name}}</h3>
                    <p class="description">{{description}}</p>
                    <div class="capability-meta">
                        <span class="version">v{{version}}</span>
                        {{#if services.length}}
                        <span class="services">{{services.length}} services</span>
                        {{/if}}
                    </div>
                    <div class="capability-details">
                        {{#if dependencies.length}}
                        <div class="dependencies">
                            <strong>Requires:</strong> {{join dependencies ", "}}
                        </div>
                        {{/if}}
                        {{#if conflicts.length}}
                        <div class="conflicts">
                            <strong>Conflicts:</strong> {{join conflicts ", "}}
                        </div>
                        {{/if}}
                    </div>
                </div>
                {{/each}}
            </div>
        </section>

        <section id="combinations">
            <h2>Supported Combinations</h2>

            <div class="filters">
                <select id="support-filter">
                    <option value="all">All Combinations</option>
                    <option value="fully_supported">Fully Supported</option>
                    <option value="conditionally_supported">Conditionally Supported</option>
                    <option value="not_supported">Not Supported</option>
                </select>

                <select id="category-filter">
                    <option value="all">All Categories</option>
                    {{#each categories}}
                    <option value="{{id}}">{{name}}</option>
                    {{/each}}
                </select>

                <input type="text" id="search" placeholder="Search combinations...">
            </div>

            <div class="combinations-grid">
                {{#each combinations}}
                <div class="combination-card {{supportLevel}}" data-support="{{supportLevel}}">
                    <div class="combination-header">
                        <h3>{{name}}</h3>
                        <span class="support-badge {{supportLevel}}">
                            {{#eq supportLevel "fully_supported"}}✅ Fully Supported{{/eq}}
                            {{#eq supportLevel "conditionally_supported"}}⚠️ Conditional{{/eq}}
                            {{#eq supportLevel "not_supported"}}❌ Not Supported{{/eq}}
                        </span>
                    </div>

                    <div class="capabilities-list">
                        {{#each capabilities}}
                        <span class="capability-tag">{{lookup ../capabilities @this 'name'}}</span>
                        {{/each}}
                    </div>

                    {{#if conditions.length}}
                    <div class="conditions">
                        <h4>Conditions:</h4>
                        <ul>
                            {{#each conditions}}
                            <li>{{this}}</li>
                            {{/each}}
                        </ul>
                    </div>
                    {{/if}}

                    <div class="test-results">
                        <div class="result-item {{#if testResults.functional.passed}}passed{{else}}failed{{/if}}">
                            Functional: {{testResults.functional.checks}} checks
                        </div>
                        <div class="result-item {{#if testResults.performance.passed}}passed{{else}}failed{{/if}}">
                            Performance: {{testResults.performance.cpuMax}}% CPU
                        </div>
                        <div class="result-item {{#if testResults.security.passed}}passed{{else}}failed{{/if}}">
                            Security: {{#if testResults.security.vulnerabilities}}⚠️{{else}}✅{{/if}}
                        </div>
                    </div>

                    <div class="combination-actions">
                        <a href="#config-{{id}}" class="btn-config">View Config</a>
                        <a href="#docs-{{id}}" class="btn-docs">Documentation</a>
                        <a href="#tests-{{id}}" class="btn-tests">Test Results</a>
                    </div>
                </div>
                {{/each}}
            </div>
        </section>

        <section id="compatibility">
            <h2>Capability Compatibility Matrix</h2>
            <div class="matrix-container">
                <table class="compatibility-matrix">
                    <thead>
                        <tr>
                            <th>Capability</th>
                            {{#each capabilities}}
                            <th class="rotate">{{name}}</th>
                            {{/each}}
                        </tr>
                    </thead>
                    <tbody>
                        {{#each capabilities}}
                        <tr>
                            <th>{{name}}</th>
                            {{#each ../capabilities}}
                            <td class="compatibility-cell {{lookup ../../compatibilityMatrix ../id this.id}}">
                                {{#eq (lookup ../../compatibilityMatrix ../id this.id) "compatible"}}✅{{/eq}}
                                {{#eq (lookup ../../compatibilityMatrix ../id this.id) "conditional"}}⚠️{{/eq}}
                                {{#eq (lookup ../../compatibilityMatrix ../id this.id) "incompatible"}}❌{{/eq}}
                                {{#eq (lookup ../../compatibilityMatrix ../id this.id) "untested"}}❓{{/eq}}
                            </td>
                            {{/each}}
                        </tr>
                        {{/each}}
                    </tbody>
                </table>
            </div>
        </section>

        <section id="examples">
            <h2>Configuration Examples</h2>
            {{#each combinations}}
            {{#eq supportLevel "fully_supported"}}
            <div id="config-{{id}}" class="example-card">
                <h3>{{name}} Configuration</h3>
                <div class="example-meta">
                    <span>Last tested: {{testResults.lastTested}}</span>
                    <span>Framework: {{compatibility.frameworkVersions.0}}</span>
                </div>
                <pre><code class="language-nix">{{include configuration.exampleFile}}</code></pre>
                <div class="example-actions">
                    <a href="{{configuration.exampleFile}}" class="btn-download">Download</a>
                    <a href="#tests-{{id}}" class="btn-test">View Test Results</a>
                </div>
            </div>
            {{/eq}}
            {{/each}}
        </section>
    </main>

    <footer>
        <p>© 2024 NixOS Gateway Framework. This support matrix is automatically generated from test results.</p>
        <p><a href="https://github.com/yourorg/nixos-gateway">View on GitHub</a> | <a href="mailto:support@yourorg.com">Contact Support</a></p>
    </footer>

    <script src="app.js"></script>
</body>
</html>
```

## PDF Documentation Template

### LaTeX Template for Official Documentation
```latex
\documentclass[11pt,a4paper]{article}
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{geometry}
\geometry{margin=1in}
\usepackage{hyperref}
\usepackage{longtable}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{colortbl}

% Define support level colors
\definecolor{fullysupported}{RGB}{34,197,94}
\definecolor{conditionalsupported}{RGB}{251,191,36}
\definecolor{notsupported}{RGB}{239,68,68}

\title{NixOS Gateway Framework\\Support Matrix}
\author{NixOS Gateway Team}
\date{\today}

\begin{document}

\maketitle

\begin{abstract}
This document provides the official support matrix for the NixOS Gateway Framework. It details which feature combinations are tested, supported, and recommended for production use. Only combinations marked as "Fully Supported" are eligible for full customer support.
\end{abstract}

\tableofcontents
\newpage

\section{Support Overview}

As of \today, the NixOS Gateway Framework has tested \textbf{150} feature combinations:

\begin{itemize}
\item \textcolor{fullysupported}{\textbf{89 Fully Supported}} - Production-ready with full support
\item \textcolor{conditionalsupported}{\textbf{34 Conditionally Supported}} - Works with limitations
\item \textcolor{notsupported}{\textbf{27 Not Supported}} - Known issues or untested
\end{itemize}

\subsection{Support Level Definitions}

\begin{description}
\item[Fully Supported] Thoroughly tested combination with all validation checks passing. Full production support available.
\item[Conditionally Supported] Works but requires specific configuration or has known limitations. Support available with conditions met.
\item[Not Supported] Not tested or has known compatibility issues. Support not available.
\end{description}

\section{Supported Combinations}

\begin{longtable}{@{}p{0.6\textwidth}p{0.15\textwidth}p{0.15\textwidth}@{}}
\caption{Supported Feature Combinations}\\
\toprule
\textbf{Combination} & \textbf{Support Level} & \textbf{Test Status} \\
\midrule
\endfirsthead

\caption[]{Supported Feature Combinations (continued)}\\
\toprule
\textbf{Combination} & \textbf{Support Level} & \textbf{Test Status} \\
\midrule
\endhead

\midrule
\multicolumn{3}{r}{\textit{Continued on next page}} \\
\endfoot

\endlastfoot

{{#each combinations}}
{{name}} &
{{#eq supportLevel "fully_supported"}}\cellcolor{fullysupported!25}Fully Supported{{/eq}}
{{#eq supportLevel "conditionally_supported"}}\cellcolor{conditionalsupported!25}Conditional{{/eq}}
{{#eq supportLevel "not_supported"}}\cellcolor{notsupported!25}Not Supported{{/eq}} &
{{#if testResults.lastTested}}{{testResults.lastTested}}{{else}}Untested{{/if}} \\

{{#if conditions}}
\textbf{Conditions:}
\begin{itemize}
{{#each conditions}}
\item {{this}}
{{/each}}
\end{itemize}
{{/if}}

{{#if limitations}}
\textbf{Limitations:}
\begin{itemize}
{{#each limitations}}
\item {{this}}
{{/each}}
\end{itemize}
{{/if}}
\\
{{/each}}
\end{longtable}

\section{Configuration Examples}

{{#each combinations}}
{{#eq supportLevel "fully_supported"}}
\subsection{{{name}}}

\textbf{Last Tested:} {{testResults.lastTested}}\\
\textbf{Framework Version:} {{compatibility.frameworkVersions.0}}\\
\textbf{Minimum Resources:} {{configuration.minimumResources.cpuCores}} CPU cores, {{configuration.minimumResources.memoryGB}}GB RAM, {{configuration.minimumResources.diskGB}}GB disk

\subsubsection{Configuration}
\inputminted[numbers=left,frame=lines]{nix}{{{configuration.exampleFile}}}

\subsubsection{Test Results Summary}
\begin{tabular}{@{}ll@{}}
\toprule
\textbf{Category} & \textbf{Result} \\
\midrule
Functional & {{#if testResults.functional.passed}}\textcolor{fullysupported}{PASS}{{else}}\textcolor{notsupported}{FAIL}{{/if}} ({{testResults.functional.checks}} checks) \\
Performance & {{#if testResults.performance.passed}}\textcolor{fullysupported}{PASS}{{else}}\textcolor{notsupported}{FAIL}{{/if}} ({{testResults.performance.cpuMax}}\% CPU max) \\
Security & {{#if testResults.security.passed}}\textcolor{fullysupported}{PASS}{{else}}\textcolor{notsupported}{FAIL}{{/if}} ({{testResults.security.vulnerabilities}} vulnerabilities) \\
Error Handling & {{#if testResults.errorHandling.passed}}\textcolor{fullysupported}{PASS}{{else}}\textcolor{notsupported}{FAIL}{{/if}} ({{testResults.errorHandling.recoveryTimeSeconds}}s recovery) \\
Integration & {{#if testResults.integration.passed}}\textcolor{fullysupported}{PASS}{{else}}\textcolor{notsupported}{FAIL}{{/if}} ({{testResults.integration.crossServiceCalls}} service calls) \\
Documentation & {{#if testResults.documentation.passed}}\textcolor{fullysupported}{PASS}{{else}}\textcolor{notsupported}{FAIL}{{/if}} (complete) \\
\bottomrule
\end{tabular}

{{/eq}}
{{/each}}

\section{Compatibility Matrix}

\begin{table}[H]
\centering
\caption{Capability Pairwise Compatibility}
\label{tab:compatibility}
\begin{tabular}{@{}l{{#each capabilities}}c{{/each}}@{}}
\toprule
\textbf{Capability} & {{#each capabilities}}\textbf{{{name}}} & {{/each}}\\
\midrule
{{#each capabilities}}
{{name}} &
{{#each ../capabilities}}
{{#eq (lookup ../../compatibilityMatrix ../id this.id) "compatible"}}\cellcolor{fullysupported!25}\checkmark{{/eq}}
{{#eq (lookup ../../compatibilityMatrix ../id this.id) "conditional"}}\cellcolor{conditionalsupported!25}$\sim${{/eq}}
{{#eq (lookup ../../compatibilityMatrix ../id this.id) "incompatible"}}\cellcolor{notsupported!25}$\times${{/eq}}
{{#eq (lookup ../../compatibilityMatrix ../id this.id) "untested"}}\cellcolor{gray!25}?{{/eq}} &
{{/each}}\\
{{/each}}
\bottomrule
\end{tabular}
\end{table}

\section{Support and Contact}

For questions about supported combinations:
\begin{itemize}
\item Review the online support matrix at \url{https://support.nixos-gateway.com/matrix}
\item Check configuration examples in the framework repository
\item Contact support for Fully Supported combinations only
\item File issues for unsupported combinations that should be tested
\end{itemize}

\textbf{Important:} Support is only available for Fully Supported combinations. Conditionally Supported combinations require meeting all specified conditions.

\end{document}
```

## Customer Email Template

### Support Request Response Template
```markdown
Subject: NixOS Gateway Support - {{combination.name}} Configuration

Dear {{customer.name}},

Thank you for your inquiry about {{combination.name}} configuration in the NixOS Gateway Framework.

## Support Status
**Status:** {{combination.supportLevel | titleCase}}
**Last Tested:** {{combination.testResults.lastTested}}
**Framework Version:** {{combination.compatibility.frameworkVersions[0]}}

## Configuration Assessment
{{#eq combination.supportLevel "fully_supported"}}
✅ **This configuration is Fully Supported**

Your configuration combines: {{combination.capabilities | join ", "}}

This combination has passed all validation checks:
- Functional testing: ✅ ({{combination.testResults.functional.checks}} checks passed)
- Performance testing: ✅ (CPU max: {{combination.testResults.performance.cpuMax}}%)
- Security validation: ✅ ({{combination.testResults.security.vulnerabilities}} vulnerabilities found)
- Error handling: ✅ ({{combination.testResults.errorHandling.recoveryTimeSeconds}}s recovery time)

You can proceed with confidence. Full support is available for this configuration.
{{/eq}}

{{#eq combination.supportLevel "conditionally_supported"}}
⚠️ **This configuration is Conditionally Supported**

Your configuration combines: {{combination.capabilities | join ", "}}

This combination works but has the following conditions:
{{#each combination.conditions}}
- {{this}}
{{/each}}

Please ensure these conditions are met before deployment. Support is available if conditions are satisfied.
{{/eq}}

{{#eq combination.supportLevel "not_supported"}}
❌ **This configuration is Not Supported**

Your configuration combines: {{combination.capabilities | join ", "}}

This combination has not been tested or has known compatibility issues. We recommend using a Fully Supported combination instead.

Alternative recommendations:
- Consider {{suggested_alternatives | join ", "}}
- Review our supported combinations at https://support.nixos-gateway.com/matrix
{{/eq}}

## Recommended Actions
{{#eq combination.supportLevel "fully_supported"}}
1. Proceed with your current configuration
2. Monitor the framework release notes for updates
3. Contact support if you encounter issues
{{/eq}}

{{#eq combination.supportLevel "conditionally_supported"}}
1. Verify all conditions are met in your environment
2. Test thoroughly in a staging environment
3. Contact support for assistance with conditions
{{/eq}}

{{#eq combination.supportLevel "not_supported"}}
1. Review alternative supported combinations
2. Consider breaking down into smaller, supported combinations
3. Request testing of this combination if it's critical to your use case
{{/eq}}

## Resources
- **Support Matrix:** https://support.nixos-gateway.com/matrix
- **Configuration Examples:** https://docs.nixos-gateway.com/examples
- **Documentation:** https://docs.nixos-gateway.com/{{combination.id}}

If you have additional questions, please don't hesitate to ask.

Best regards,  
NixOS Gateway Support Team  
support@nixos-gateway.com  
https://support.nixos-gateway.com
```

## API Documentation Template

### OpenAPI Specification for Support Matrix API
```yaml
openapi: 3.0.3
info:
  title: NixOS Gateway Support Matrix API
  version: 1.0.0
  description: REST API for accessing the official NixOS Gateway support matrix

servers:
  - url: https://api.nixos-gateway.com/v1
    description: Production server

paths:
  /matrix:
    get:
      summary: Get complete support matrix
      responses:
        '200':
          description: Complete support matrix
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/SupportMatrix'

  /matrix/combinations:
    get:
      summary: Get supported combinations
      parameters:
        - name: supportLevel
          in: query
          schema:
            type: string
            enum: [fully_supported, conditionally_supported, not_supported]
        - name: capability
          in: query
          schema:
            type: string
      responses:
        '200':
          description: Filtered combinations
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Combination'

  /matrix/combinations/{id}:
    get:
      summary: Get specific combination details
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Combination details
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Combination'

  /matrix/capabilities:
    get:
      summary: Get available capabilities
      responses:
        '200':
          description: List of capabilities
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Capability'

  /matrix/validate:
    post:
      summary: Validate a configuration against support matrix
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                capabilities:
                  type: array
                  items:
                    type: string
                configuration:
                  type: object
      responses:
        '200':
          description: Validation result
          content:
            application/json:
              schema:
                type: object
                properties:
                  valid: { type: boolean }
                  supportLevel: { type: string }
                  issues: { type: array, items: { type: string } }
                  recommendations: { type: array, items: { type: string } }

components:
  schemas:
    SupportMatrix:
      type: object
      properties:
        metadata: { $ref: '#/components/schemas/Metadata' }
        capabilities: { type: array, items: { $ref: '#/components/schemas/Capability' } }
        combinations: { type: array, items: { $ref: '#/components/schemas/Combination' } }

    Metadata:
      type: object
      properties:
        version: { type: string }
        lastUpdated: { type: string, format: date-time }
        frameworkVersion: { type: string }
        totalCombinations: { type: integer }
        supportedCombinations: { type: integer }

    Capability:
      type: object
      properties:
        id: { type: string }
        name: { type: string }
        category: { type: string, enum: [core, networking, security, monitoring, services, infrastructure] }
        version: { type: string }
        services: { type: array, items: { type: string } }
        dependencies: { type: array, items: { type: string } }
        conflicts: { type: array, items: { type: string } }

    Combination:
      type: object
      properties:
        id: { type: string }
        name: { type: string }
        capabilities: { type: array, items: { type: string } }
        supportLevel: { type: string, enum: [fully_supported, conditionally_supported, not_supported] }
        conditions: { type: array, items: { type: string } }
        testResults: { $ref: '#/components/schemas/TestResults' }

    TestResults:
      type: object
      properties:
        lastTested: { type: string, format: date }
        functional: { $ref: '#/components/schemas/TestCategory' }
        performance: { $ref: '#/components/schemas/TestCategory' }
        security: { $ref: '#/components/schemas/TestCategory' }
        errorHandling: { $ref: '#/components/schemas/TestCategory' }
        integration: { $ref: '#/components/schemas/TestCategory' }
        documentation: { $ref: '#/components/schemas/TestCategory' }

    TestCategory:
      type: object
      properties:
        passed: { type: boolean }
        notes: { type: string }
```

These templates provide comprehensive customer-facing documentation that clearly communicates support boundaries, provides actionable guidance, and maintains professional presentation of the support matrix.
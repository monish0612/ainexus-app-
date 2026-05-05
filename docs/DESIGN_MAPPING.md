# Design → Flutter Mapping Reference

> Place this file alongside ARCHITECTURE.md. It maps each HTML design element to the exact Flutter widget pattern.

---

## Global Mappings (All Screens)

| HTML/CSS | Flutter Equivalent |
|---|---|
| `bg-background-dark` (#000000) | `Scaffold(backgroundColor: AppColors.backgroundDark)` |
| `font-display` (Manrope) | `fontFamily: 'Manrope'` in ThemeData |
| `font-modern` (Space Grotesk) | `fontFamily: 'SpaceGrotesk'` — launch screen only |
| `backdrop-filter: blur(12px)` | `ClipRRect` + `BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12))` |
| `bg-white/3 border-white/8` | `GlassCard` widget (custom) |
| `bg-primary/5 border-primary/15` | `GlassCard` with primaryGlass colors |
| `rounded-xl` (1.5rem) | `BorderRadius.circular(24)` |
| `rounded-lg` (1rem) | `BorderRadius.circular(16)` |
| `rounded-full` (9999px) | `BorderRadius.circular(50)` or `BoxShape.circle` |
| `text-slate-100` | `AppColors.textPrimary` (#F1F5F9) |
| `text-slate-400` | `AppColors.textSecondary` (#94A3B8) |
| `text-slate-500` | `AppColors.textTertiary` (#64748B) |
| `text-primary` | `AppColors.primary` (#4725F4) |
| `font-bold` (700) | `FontWeight.w700` |
| `font-extrabold` (800) | `FontWeight.w800` |
| `tracking-tight` (-0.025em) | `letterSpacing: -0.5` |
| `tracking-widest` (0.1em) | `letterSpacing: 1.5` |
| `uppercase` | `.toUpperCase()` in Text |
| Material Symbols Outlined icons | `Icons.xxx_rounded` or `Icons.xxx_outlined` from Material |

---

## Bottom Nav Icon Mapping

| HTML Icon | Flutter Icon (active) | Flutter Icon (inactive) |
|---|---|---|
| `home` / `house` | `Icons.home_rounded` | `Icons.home_outlined` |
| `monitoring` / `pie_chart` | `Icons.pie_chart_rounded` | `Icons.pie_chart_outline_rounded` |
| `explore` | `Icons.explore_rounded` | `Icons.explore_outlined` |
| `smart_toy` / `auto_awesome` | `Icons.auto_awesome_rounded` | `Icons.auto_awesome_outlined` |
| `settings` | `Icons.settings_rounded` | `Icons.settings_outlined` |

---

## Screen-by-Screen HTML → Flutter

### Launch Screen (Launch_code.html)
| HTML Element | Flutter Widget |
|---|---|
| `.orb-glow` div with gradient circle | `Container` with `BoxDecoration(shape: circle, gradient, boxShadow)` |
| `blur_on` material icon 5xl | `Icon(Icons.blur_on_rounded, size: 56)` |
| `.gradient-button` | `DecoratedBox(gradient)` + `Material` + `InkWell` |
| `font-modern text-5xl font-bold` | `Text('AI ', style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 48, fontWeight: w700))` |
| `bg-clip-text text-transparent bg-gradient` | `ShaderMask(shaderCallback: gradient.createShader, child: Text(..., color: Colors.white))` |
| Page indicators `w-8 h-1 bg-primary` | `Container(width: 28, height: 4, decoration: BoxDecoration(color: primary, borderRadius))` |

### Home Screen (homepage_code.html)
| HTML Element | Flutter Widget |
|---|---|
| `.gradient-card` with balance | `GradientCard` widget (custom) with `LinearGradient` |
| `contactless` icon | `Icon(Icons.contactless_rounded)` |
| SVG donut chart (`<svg viewBox="0 0 100 100">`) | `CustomPaint(painter: DonutChartPainter())` using `canvas.drawArc()` |
| `.glow-active` text-shadow | `TextStyle(shadows: [Shadow(color: primary.withOpacity(0.5), blurRadius: 12)])` |
| Mini bar charts in activity | `Row` of `FractionallySizedBox(heightFactor: x, child: Container(borderRadius: 20))` |
| `.fab-glow` floating button | `FloatingActionButton` with `BoxShadow` |
| `magic_button` icon | `Icon(Icons.auto_awesome, size: 16)` |

### Insights Screen (analytics_code.html)
| HTML Element | Flutter Widget |
|---|---|
| Radio-button timeframe selector | `SegmentedToggle` widget (custom) |
| SVG area chart with gradient fill | `CustomPaint(painter: AreaChartPainter())` using `Path` + `canvas.drawPath` |
| `.glass-card` category grid | `GridView.count(crossAxisCount: 2)` with `GlassCard` children |
| `.glow-icon` text-shadow on icons | `BoxDecoration(color: color.withOpacity(0.15))` — skip text-shadow, use colored bg |
| Progress bars `h-1 bg-primary` | `ClipRRect + LinearProgressIndicator(value: x, minHeight: 4)` |

### Discover Screen (rss_feed_news_code.html)
| HTML Element | Flutter Widget |
|---|---|
| Sticky header with pull-to-refresh hint | `CustomScrollView` + `SliverToBoxAdapter` |
| Overflow-x filter chips | `SingleChildScrollView(scrollDirection: Axis.horizontal)` → `FilterChipRow` |
| Article card with 16:9 image | `AspectRatio(aspectRatio: 16/9)` inside glass card |
| `auto_awesome` AI badge | `AiBadge` widget (custom) |
| `line-clamp-2` text | `Text(maxLines: 2, overflow: TextOverflow.ellipsis)` |
| `group-hover:scale-105` image zoom | Skip for mobile — not applicable |

### AI Coach Screen (AI_Coach_code.html)
| HTML Element | Flutter Widget |
|---|---|
| Tab bar with active underline | Row of `GestureDetector` with `Border(bottom: BorderSide)` |
| Textarea `min-h-[120px]` | `TextField(maxLines: 5, maxLength: 500)` |
| Mic button `.glow-accent` | `Container(shape: circle, color: primary, boxShadow: [accentBlue glow])` |
| Green `check_circle` + PERFECTED | `Row(Icon(Icons.check_circle, color: success), Text('PERFECTED'))` |
| Tone tags `bg-emerald-500/20` | `Container(color: success.withOpacity(0.15), borderRadius: 4)` |
| Platform buttons with icons | `Container` with icon + text, glass background |
| Left-bordered variation preview | `Container(decoration: BoxDecoration(border: Border(left: BorderSide(primary, 2))))` |
| `lightbulb` pro-tip icon in cyan bg | `Container(color: accentBlue.withOpacity(0.15))` + `Icon(Icons.lightbulb)` |

### Settings Screen (settings_code.html)
| HTML Element | Flutter Widget |
|---|---|
| Avatar with gradient ring + glow | `Container(gradient border, boxShadow: [primary glow])` → `CircleAvatar` |
| Edit button on avatar | `Positioned(bottom: 1, right: 1)` inside Stack |
| `AI PREMIUM` badge | `Container(color: primary.withOpacity(0.2), borderRadius: 20)` |
| Theme toggle AMOLED/White | `SegmentedToggle` widget |
| Settings tiles with chevron | `GlassCard` + `Row(icon, Column(title, subtitle), Icon(chevron_right))` |
| Sign Out button red border | `OutlinedButton(side: BorderSide(color: error.withOpacity(0.3)))` |

---

## SVG Chart Formulas

### Donut Chart (Home)
```
Segments: food 40%, transport 25%, shopping 20%, others 15%
canvas.drawArc(rect, startAngle, sweepAngle, false, paint)
startAngle begins at -π/2 (12 o'clock)
Each segment: sweepAngle = 2π × percentage
strokeWidth: 14, strokeCap: StrokeCap.round
Add 0.02 rad gap between segments
```

### Area Chart (Insights)
```
7 data points (Mon-Sun), connected with cubic bezier
Control points: cp1 = (midX, prevY), cp2 = (midX, currY)
Fill: Path from line → bottom-right → bottom-left → close, paint with LinearGradient (primary 40%→0%)
Line: same path, stroke primary 3px
Dots: 3 circles at notable peaks, radius 5, fill primary
```

### Mini Donut (Insights category)
```
3 segments: food 70%, shopping 25%, others 5%
Same drawArc technique, strokeWidth: 10
Center text: "70%" + "FOOD"
```

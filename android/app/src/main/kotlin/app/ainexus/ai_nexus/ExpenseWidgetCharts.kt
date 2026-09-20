package app.ainexus.ai_nexus

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.min

/**
 * Bitmap donut for the Expense widget. RemoteViews cannot host a real chart
 * view, so [ExpenseWidgetProvider] ships a pre-drawn ring via
 * `setImageViewBitmap`. Keep this tiny — large bitmaps are dropped by launchers.
 */
object ExpenseWidgetCharts {

    private val FALLBACK_COLORS = intArrayOf(
        0xFF22D3EE.toInt(),
        0xFFA78BFA.toInt(),
        0xFFF472B6.toInt(),
        0xFF34D399.toInt(),
    )

    /**
     * Draws a hollow spend-mix ring. Transparent centre so the month total
     * TextView sitting on top of the ImageView stays readable. Returns null
     * if there is nothing to draw or the canvas cannot be allocated.
     */
    fun donutBitmap(
        slices: List<ExpenseWidgetLogic.PieSlice>,
        sizePx: Int,
    ): Bitmap? {
        if (sizePx <= 8) return null
        val sweeps = ExpenseWidgetLogic.pieSweeps(slices)
        if (sweeps.isEmpty()) return null
        return try {
            val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            val stroke = sizePx * 0.168f
            val pad = stroke / 2f + sizePx * 0.045f
            val oval = RectF(pad, pad, sizePx - pad, sizePx - pad)

            val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                color = 0x1AFFFFFF
                strokeCap = Paint.Cap.BUTT
            }
            canvas.drawOval(oval, track)

            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.BUTT
            }
            sweeps.forEachIndexed { i, sw ->
                paint.color = ExpenseWidgetLogic.parseHexColor(sw.slice.colorHex)
                    ?: FALLBACK_COLORS[i % FALLBACK_COLORS.size]
                canvas.drawArc(oval, sw.startAngle, sw.sweep, false, paint)
            }

            // Soft inner rim so the hole reads as glass, not a cut-out.
            val cx = sizePx / 2f
            val cy = sizePx / 2f
            val innerR = (min(oval.width(), oval.height()) / 2f) - stroke * 0.48f
            if (innerR > 0f) {
                val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = sizePx * 0.012f
                    color = 0x14FFFFFF
                }
                canvas.drawCircle(cx, cy, innerR, rim)
            }
            bmp
        } catch (_: Exception) {
            null
        }
    }
}

import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/bar_chart/bar_chart_data.dart';
import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_painter.dart';
import 'package:fl_chart/src/chart/base/base_chart/base_chart_painter.dart';
import 'package:fl_chart/src/utils/canvas_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../utils/utils.dart';

/// Paints [BarChartData] in the canvas, it can be used in a [CustomPainter]
class BarChartPainter extends AxisChartPainter<BarChartData> with TouchHandler<BarTouchResponse> {
  Paint _barPaint, _bgTouchTooltipPaint;

  List<_GroupBarsPosition> _groupBarsPosition;

  double _nextStepTime = 0;

  /// Paints [data] into canvas, it is the animating [BarChartData],
  /// [targetData] is the animation's target and remains the same
  /// during animation, then we should use it  when we need to show
  /// tooltips or something like that, because [data] is changing constantly.
  ///
  /// [touchHandler] passes a [TouchHandler] to the parent,
  /// parent will use it for touch handling flow.
  ///
  /// [textScale] used for scaling texts inside the chart,
  /// parent can use [MediaQuery.textScaleFactor] to respect
  /// the system's font size.
  BarChartPainter(BarChartData data, BarChartData targetData, Function(TouchHandler) touchHandler,
      {double textScale = 1})
      : super(data, targetData, textScale: textScale) {
    touchHandler(this);
    _barPaint = Paint()
      ..style = PaintingStyle.fill;

    _bgTouchTooltipPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
  }

  /// Paints [BarChartData] into the provided canvas.
  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    final canvasWrapper = CanvasWrapper(canvas, size);

    if (data.barGroups.isEmpty) {
      return;
    }

    final groupsX = _calculateGroupsX(size, data.barGroups, data.alignment);
    _groupBarsPosition = _calculateGroupAndBarsPosition(size, groupsX, data.barGroups);

    _drawBars(canvasWrapper, _groupBarsPosition);
    drawAxisTitles(canvasWrapper);
    _drawTitles(canvasWrapper, _groupBarsPosition);

    for (var i = 0; i < targetData.barGroups.length; i++) {
      final barGroup = targetData.barGroups[i];
      for (var j = 0; j < barGroup.barRods.length; j++) {
        if (!barGroup.showingTooltipIndicators.contains(j)) {
          continue;
        }
        final barRod = barGroup.barRods[j];

        _drawTouchTooltip(
            canvasWrapper,
            _groupBarsPosition,
            targetData.barTouchData.touchTooltipData,
            barGroup,
            i,
            barRod,
            j);
      }
    }
  }

  /// Calculates groups position for showing in the x axis using [alignment].
  List<double> _calculateGroupsX(Size viewSize, List<BarChartGroupData> barGroups, BarChartAlignment alignment) {
    final drawSize = getChartUsableDrawSize(viewSize);

    final groupsX = List.filled(barGroups.length, 0.0, growable: false);

    final leftTextsSpace = getLeftOffsetDrawSize();

    switch (alignment) {
      case BarChartAlignment.start:
        var tempX = 0.0;
        barGroups.asMap().forEach((i, group) {
          groupsX[i] = leftTextsSpace + tempX + group.width / 2;
          tempX += group.width;
        });
        break;

      case BarChartAlignment.end:
        var tempX = 0.0;
        for (var i = barGroups.length - 1; i >= 0; i--) {
          final group = barGroups[i];
          groupsX[i] = (leftTextsSpace + drawSize.width) - tempX - group.width / 2;
          tempX += group.width;
        }
        break;

      case BarChartAlignment.center:
        var sumWidth = barGroups.map((group) => group.width).reduce((a, b) => a + b);
        sumWidth += data.groupsSpace * (barGroups.length - 1);
        final horizontalMargin = (drawSize.width - sumWidth) / 2;

        var tempX = 0.0;
        for (var i = 0; i < barGroups.length; i++) {
          final group = barGroups[i];
          groupsX[i] = leftTextsSpace + horizontalMargin + tempX + group.width / 2;

          final groupSpace = i == barGroups.length - 1 ? 0 : data.groupsSpace;
          tempX += group.width + groupSpace;
        }
        break;

      case BarChartAlignment.spaceBetween:
        final sumWidth = barGroups.map((group) => group.width).reduce((a, b) => a + b);
        final spaceAvailable = drawSize.width - sumWidth;
        final eachSpace = spaceAvailable / (barGroups.length - 1);

        var tempX = 0.0;
        barGroups.asMap().forEach((index, group) {
          tempX += group.width / 2;
          if (index != 0) {
            tempX += eachSpace;
          }
          groupsX[index] = leftTextsSpace + tempX;
          tempX += group.width / 2;
        });
        break;

      case BarChartAlignment.spaceAround:
        final sumWidth = barGroups.map((group) => group.width).reduce((a, b) => a + b);
        final spaceAvailable = drawSize.width - sumWidth;
        final eachSpace = spaceAvailable / (barGroups.length * 2);

        var tempX = 0.0;
        barGroups.asMap().forEach((i, group) {
          tempX += eachSpace;
          tempX += group.width / 2;
          groupsX[i] = leftTextsSpace + tempX;
          tempX += group.width / 2;
          tempX += eachSpace;
        });
        break;

      case BarChartAlignment.spaceEvenly:
        final sumWidth = barGroups.map((group) => group.width).reduce((a, b) => a + b);
        final spaceAvailable = drawSize.width - sumWidth;
        final eachSpace = spaceAvailable / (barGroups.length + 1);

        var tempX = 0.0;
        barGroups.asMap().forEach((i, group) {
          tempX += eachSpace;
          tempX += group.width / 2;
          groupsX[i] = leftTextsSpace + tempX;
          tempX += group.width / 2;
        });
        break;
    }

    return groupsX;
  }

  /// Calculates bars position alongside group positions.
  List<_GroupBarsPosition> _calculateGroupAndBarsPosition(Size viewSize, List<double> groupsX,
      List<BarChartGroupData> barGroups) {
    if (groupsX.length != barGroups.length) {
      throw Exception('inconsistent state groupsX.length != barGroups.length');
    }

    final groupBarsPosition = <_GroupBarsPosition>[];
    for (var i = 0; i < barGroups.length; i++) {
      final barGroup = barGroups[i];
      final groupX = groupsX[i];

      var tempX = 0.0;
      final barsX = <double>[];
      barGroup.barRods.asMap().forEach((barIndex, barRod) {
        final widthHalf = barRod.width / 2;
        barsX.add(groupX - (barGroup.width / 2) + tempX + widthHalf);
        tempX += barRod.width + barGroup.barsSpace;
      });
      groupBarsPosition.add(_GroupBarsPosition(groupX, barsX));
    }
    return groupBarsPosition;
  }

  void _drawBars(CanvasWrapper canvasWrapper, List<_GroupBarsPosition> groupBarsPosition) {
    final viewSize = canvasWrapper.size;
    final drawSize = getChartUsableDrawSize(viewSize);

    for (var i = 0; i < data.barGroups.length; i++) {
      final barGroup = data.barGroups[i];
      for (var j = 0; j < barGroup.barRods.length; j++) {
        final barRod = barGroup.barRods[j];
        final widthHalf = barRod.width / 4;
        final borderRadius = barRod.borderRadius ?? BorderRadius.circular(barRod.width / 4);

        final x = groupBarsPosition[i].barsX[j];

        final left = x - widthHalf;
        final right = x + widthHalf;
        final cornerHeight = max(borderRadius.topLeft.y, borderRadius.topRight.y) +
            max(borderRadius.bottomLeft.y, borderRadius.bottomRight.y);
        RRect barRRect;
        // draw Main Rod
        if (barRod.y != 0) {
          if (barRod.y > 0 && barGroup.barList.length != null) {
            for (var i = 0; i < barGroup.barList.length; i++) {
              // positive
              var minValue = barGroup.barList[i].bottom;
              var maxValue = barGroup.barList[i].top;

              if (data.typeChart == TypeChart.Sleep) {
                minValue = Duration(milliseconds: (minValue - data.timeStart).toInt()).inMinutes.toDouble();
                maxValue = Duration(milliseconds: (maxValue - data.timeStart).toInt()).inMinutes.toDouble();
              }

              final bottom = getPixelY(minValue ?? 0, drawSize);
              final top = min(getPixelY(maxValue ?? 0, drawSize), bottom - cornerHeight);

              final barRRect = RRect.fromLTRBAndCorners(left, top, right, bottom,
                  topLeft: borderRadius.topLeft,
                  topRight: borderRadius.topRight,
                  bottomLeft: borderRadius.bottomLeft,
                  bottomRight: borderRadius.bottomRight);

              _barPaint.color = barGroup.barList[i].primaryColor;

              canvasWrapper.drawRRect(barRRect, _barPaint);
            }
          }
        }
      }
    }
  }

  void _drawTitles(CanvasWrapper canvasWrapper, List<_GroupBarsPosition> groupBarsPosition) {
    if (!targetData.titlesData.show) {
      return;
    }
    final viewSize = canvasWrapper.size;
    final drawSize = getChartUsableDrawSize(viewSize);

    // Left Titles
    final leftTitles = targetData.titlesData.leftTitles;
    final leftInterval =
        leftTitles.interval ?? getEfficientInterval(viewSize.height, data.verticalDiff);
    if (leftTitles.showTitles) {
      var verticalSeek = data.minY;
      while (verticalSeek <= data.maxY) {
        if (leftTitles.checkToShowTitle(
            data.minY, data.maxY, leftTitles, leftInterval, verticalSeek)) {
          var x = 0 + getLeftOffsetDrawSize();
          var y = getPixelY(verticalSeek, drawSize);

          final text = leftTitles.getTitles(verticalSeek);

          final span = TextSpan(style: leftTitles.getTextStyles(verticalSeek), text: text);
          final tp = TextPainter(
              text: span,
              textAlign: TextAlign.center,
              textDirection: ui.TextDirection.ltr,
              textScaleFactor: textScale);
          tp.layout(maxWidth: getExtraNeededHorizontalSpace());
          x -= tp.width + leftTitles.margin;
          y -= tp.height / 2;
          canvasWrapper.save();
          canvasWrapper.translate(x + tp.width / 2, y + tp.height / 2);
          canvasWrapper.rotate(radians(leftTitles.rotateAngle));
          canvasWrapper.translate(-(x + tp.width / 2), -(y + tp.height / 2));
          y -= translateRotatedPosition(tp.width, leftTitles.rotateAngle);
          canvasWrapper.drawText(tp, Offset(x, y));
          canvasWrapper.restore();
        }
        if (data.maxY - verticalSeek < leftInterval && data.maxY != verticalSeek) {
          verticalSeek = data.maxY;
        } else {
          verticalSeek += leftInterval;
        }
      }
    }

    // Top Titles
    final topTitles = targetData.titlesData.topTitles;
    if (topTitles.showTitles) {
      for (var index = 0; index < groupBarsPosition.length; index++) {
        final groupBarPos = groupBarsPosition[index];

        final xValue = data.barGroups[index].x.toDouble();
        final text = topTitles.getTitles(xValue);
        final span = TextSpan(style: topTitles.getTextStyles(xValue), text: text);
        final tp = TextPainter(
            text: span,
            textAlign: TextAlign.center,
            textDirection: ui.TextDirection.ltr,
            textScaleFactor: textScale);
        tp.layout();
        var x = groupBarPos.groupX;
        const y = 0.0;

        x -= tp.width / 2;
        canvasWrapper.save();
        canvasWrapper.translate(x + tp.width / 2, y + tp.height / 2);
        canvasWrapper.rotate(radians(topTitles.rotateAngle));
        canvasWrapper.translate(-(x + tp.width / 2), -(y + tp.height / 2));
        x += translateRotatedPosition(tp.width, topTitles.rotateAngle);
        canvasWrapper.drawText(tp, Offset(x, y));
        canvasWrapper.restore();
      }
    }

    // Right Titles
    final rightTitles = targetData.titlesData.rightTitles;
    final rightInterval =
        rightTitles.interval ?? getEfficientInterval(viewSize.height, data.verticalDiff);
    if (rightTitles.showTitles) {
      var verticalSeek = data.minY;
      while (verticalSeek <= data.maxY) {
        if (rightTitles.checkToShowTitle(
            data.minY, data.maxY, rightTitles, rightInterval, verticalSeek)) {
          var x = drawSize.width + getLeftOffsetDrawSize();
          var y = getPixelY(verticalSeek, drawSize);

          if (data.typeChart == TypeChart.HeartRate) {
            if ((verticalSeek % data.divisionValue) == 0) {
              final text = rightTitles.getTitles(verticalSeek);
              final span = TextSpan(style: rightTitles.getTextStyles(verticalSeek), text: text);
              final tp = TextPainter(
                  text: span,
                  textAlign: TextAlign.center,
                  textDirection: ui.TextDirection.ltr,
                  textScaleFactor: textScale);
              tp.layout(maxWidth: getExtraNeededHorizontalSpace());
              x += rightTitles.margin;
              y -= tp.height / 2;
              canvasWrapper.save();
              canvasWrapper.translate(x + tp.width / 2, y + tp.height / 2);
              canvasWrapper.rotate(radians(rightTitles.rotateAngle));
              canvasWrapper.translate(-(x + tp.width / 2), -(y + tp.height / 2));
              y += translateRotatedPosition(tp.width, leftTitles.rotateAngle);
              canvasWrapper.drawText(tp, Offset(x, y));
              canvasWrapper.restore();
            }
          } else if (data.typeChart == TypeChart.Sleep) {
            if (verticalSeek == data.maxY || verticalSeek == data.minY ||
                ((verticalSeek % data.divisionValue) == 0)) {
              final df = new DateFormat('h a');
              var text = "";

              if (data.minY == verticalSeek) {
                _nextStepTime = data.timeStart + (data.divisionValue * 60000);
                text = df.format(DateTime.fromMillisecondsSinceEpoch(data.timeStart.toInt()));
              } else if (verticalSeek == data.maxY) {
                text = df.format(DateTime.fromMillisecondsSinceEpoch(data.timeFinish.toInt()));
              } else {
                text = df.format(DateTime.fromMillisecondsSinceEpoch(_nextStepTime.toInt()));
                _nextStepTime = (data.divisionValue * 60000) + _nextStepTime;
              }


              // final text = rightTitles.getTitles(verticalSeek);
              final span = TextSpan(style: rightTitles.getTextStyles(verticalSeek), text: text);
              final tp = TextPainter(
                  text: span,
                  textAlign: TextAlign.left,
                  textDirection: ui.TextDirection.ltr,
                  textScaleFactor: textScale);
              tp.layout(maxWidth: getExtraNeededHorizontalSpace());
              x += rightTitles.margin;
              y -= tp.height / 2;


              canvasWrapper.save();
              canvasWrapper.translate(x + tp.width / 2, y + tp.height / 2);
              canvasWrapper.rotate(radians(rightTitles.rotateAngle));
              canvasWrapper.translate(-(x + tp.width / 2), -(y + tp.height / 2));
              y += translateRotatedPosition(tp.width, leftTitles.rotateAngle);
              canvasWrapper.drawText(tp, Offset(x, y));
              canvasWrapper.restore();
            }
          } else {
            final text = rightTitles.getTitles(verticalSeek);
            final span = TextSpan(style: rightTitles.getTextStyles(verticalSeek), text: text);

            final tp = TextPainter(
                text: span,
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
                textScaleFactor: textScale);

            tp.layout(maxWidth: getExtraNeededHorizontalSpace());
            x += rightTitles.margin;
            y -= tp.height / 2;

            canvasWrapper.save();
            canvasWrapper.translate(x + tp.width / 2, y + tp.height / 2);
            canvasWrapper.rotate(radians(rightTitles.rotateAngle));
            canvasWrapper.translate(-(x + tp.width / 2), -(y + tp.height / 2));
            y += translateRotatedPosition(tp.width, leftTitles.rotateAngle);
            canvasWrapper.drawText(tp, Offset(x, y));
            canvasWrapper.restore();
          }


          if (data.maxY - verticalSeek < rightInterval && data.maxY != verticalSeek) {
            verticalSeek = data.maxY;
          } else {
            verticalSeek += rightInterval;
          }
        }
      }
    }

    // Bottom titles
    final bottomTitles = targetData.titlesData.bottomTitles;
    if (bottomTitles.showTitles) {
      for (var index = 0; index < groupBarsPosition.length; index++) {
        final groupBarPos = groupBarsPosition[index];

        final xValue = data.barGroups[index].x.toDouble();
        final text = bottomTitles.getTitles(xValue);
        // ignore: omit_local_variable_types
        final span = TextSpan(style: bottomTitles.getTextStyles(xValue), text: text);
        final tp = TextPainter(
            text: span,
            textAlign: TextAlign.center,
            textDirection: ui.TextDirection.ltr,
            textScaleFactor: textScale);
        tp.layout();
        var x = groupBarPos.groupX;
        final y = drawSize.height + getTopOffsetDrawSize() + bottomTitles.margin;

        x -= tp.width / 2;
        canvasWrapper.save();
        canvasWrapper.translate(x + tp.width / 2, y + tp.height / 2);
        canvasWrapper.rotate(radians(bottomTitles.rotateAngle));
        canvasWrapper.translate(-(x + tp.width / 2), -(y + tp.height / 2));
        x += translateRotatedPosition(tp.width, bottomTitles.rotateAngle);
        canvasWrapper.drawText(tp, Offset(x, y));
        canvasWrapper.restore();
      }
    }
  }

  void _drawTouchTooltip(CanvasWrapper canvasWrapper,
      List<_GroupBarsPosition> groupPositions,
      BarTouchTooltipData tooltipData,
      BarChartGroupData showOnBarGroup,
      int barGroupIndex,
      BarChartRodData showOnRodData,
      int barRodIndex,) {
    final viewSize = canvasWrapper.size;
    final chartUsableSize = getChartUsableDrawSize(viewSize);

    const textsBelowMargin = 4;

    final tooltipItem = tooltipData.getTooltipItem(
      showOnBarGroup,
      barGroupIndex,
      showOnRodData,
      barRodIndex,
    );

    if (tooltipItem == null) {
      return;
    }

    final span = TextSpan(style: tooltipItem.textStyle, text: tooltipItem.text);
    final tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        textScaleFactor: textScale);
    tp.layout(maxWidth: tooltipData.maxContentWidth);

    /// creating TextPainters to calculate the width and height of the tooltip
    final drawingTextPainter = tp;

    /// biggerWidth
    /// some texts maybe larger, then we should
    /// draw the tooltip' width as wide as biggerWidth
    ///
    /// sumTextsHeight
    /// sum up all Texts height, then we should
    /// draw the tooltip's height as tall as sumTextsHeight
    final textWidth = drawingTextPainter.width;
    final textHeight = drawingTextPainter.height + textsBelowMargin;

    /// if we have multiple bar lines,
    /// there are more than one FlCandidate on touch area,
    /// we should get the most top FlSpot Offset to draw the tooltip on top of it
    final barOffset = Offset(
      groupPositions[barGroupIndex].barsX[barRodIndex],
      getPixelY(showOnRodData.y, chartUsableSize),
    );

    final isPositive = showOnRodData.y > 0;

    final tooltipWidth = textWidth + tooltipData.tooltipPadding.horizontal;
    final tooltipHeight = textHeight + tooltipData.tooltipPadding.vertical;

    final tooltipTop = isPositive
        ? barOffset.dy - tooltipHeight - tooltipData.tooltipBottomMargin
        : barOffset.dy + tooltipData.tooltipBottomMargin;

    /// draw the background rect with rounded radius
    // ignore: omit_local_variable_types
    Rect rect =
    Rect.fromLTWH(barOffset.dx - (tooltipWidth / 2), tooltipTop, tooltipWidth, tooltipHeight);

    if (tooltipData.fitInsideHorizontally) {
      if (rect.left < 0) {
        final shiftAmount = 0 - rect.left;
        rect = Rect.fromLTRB(
          rect.left + shiftAmount,
          rect.top,
          rect.right + shiftAmount,
          rect.bottom,
        );
      }

      if (rect.right > viewSize.width) {
        final shiftAmount = rect.right - viewSize.width;
        rect = Rect.fromLTRB(
          rect.left - shiftAmount,
          rect.top,
          rect.right - shiftAmount,
          rect.bottom,
        );
      }
    }

    if (tooltipData.fitInsideVertically) {
      if (rect.top < 0) {
        final shiftAmount = 0 - rect.top;
        rect = Rect.fromLTRB(
          rect.left,
          rect.top + shiftAmount,
          rect.right,
          rect.bottom + shiftAmount,
        );
      }

      if (rect.bottom > viewSize.height) {
        final shiftAmount = rect.bottom - viewSize.height;
        rect = Rect.fromLTRB(
          rect.left,
          rect.top - shiftAmount,
          rect.right,
          rect.bottom - shiftAmount,
        );
      }
    }

    final radius = Radius.circular(tooltipData.tooltipRoundedRadius);
    final roundedRect = RRect.fromRectAndCorners(rect,
        topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius);
    _bgTouchTooltipPaint.color = tooltipData.tooltipBgColor;
    canvasWrapper.drawRRect(roundedRect, _bgTouchTooltipPaint);

    /// draw the texts one by one in below of each other
    final top = tooltipData.tooltipPadding.top;
    final drawOffset = Offset(
      rect.center.dx - (tp.width / 2),
      rect.topCenter.dy + top,
    );
    canvasWrapper.drawText(tp, drawOffset);
  }

  /// We add our needed horizontal space to parent needed.
  /// we have some titles that maybe draw in the left and right side of our chart,
  /// then we should draw the chart a with some left space,
  /// the left space is [getLeftOffsetDrawSize],
  /// and the whole space is [getExtraNeededHorizontalSpace]
  @override
  double getExtraNeededHorizontalSpace() {
    var sum = super.getExtraNeededHorizontalSpace();
    if (data.titlesData.show) {
      final leftSide = data.titlesData.leftTitles;
      if (leftSide.showTitles) {
        sum += leftSide.reservedSize + leftSide.margin;
      }

      final rightSide = data.titlesData.rightTitles;
      if (rightSide.showTitles) {
        sum += rightSide.reservedSize + rightSide.margin;
      }
    }
    return sum;
  }

  /// We add our needed vertical space to parent needed.
  /// we have some titles that maybe draw in the top and bottom side of our chart,
  /// then we should draw the chart a with some top space,
  /// the top space is [getTopOffsetDrawSize()],
  /// and the whole space is [getExtraNeededVerticalSpace]
  @override
  double getExtraNeededVerticalSpace() {
    var sum = super.getExtraNeededVerticalSpace();
    if (data.titlesData.show) {
      final bottomSide = data.titlesData.bottomTitles;
      if (bottomSide.showTitles) {
        sum += bottomSide.reservedSize + bottomSide.margin;
      }

      final topSide = data.titlesData.topTitles;
      if (topSide.showTitles) {
        sum += topSide.reservedSize + topSide.margin;
      }
    }
    return sum;
  }

  /// calculate left offset for draw the chart,
  /// maybe we want to show both left and right titles,
  /// then just the left titles will effect on this function.
  @override
  double getLeftOffsetDrawSize() {
    var sum = super.getLeftOffsetDrawSize();

    final leftTitles = data.titlesData.leftTitles;
    if (data.titlesData.show && leftTitles.showTitles) {
      sum += leftTitles.reservedSize + leftTitles.margin;
    }

    return sum;
  }

  /// calculate top offset for draw the chart,
  /// maybe we want to show both top and bottom titles,
  /// then just the top titles will effect on this function.
  @override
  double getTopOffsetDrawSize() {
    var sum = super.getTopOffsetDrawSize();

    final topTitles = data.titlesData.topTitles;
    if (data.titlesData.show && topTitles.showTitles) {
      sum += topTitles.reservedSize + topTitles.margin;
    }

    return sum;
  }

  /// Makes a [BarTouchResponse] based on the provided [FlTouchInput]
  ///
  /// Processes [FlTouchInput.getOffset] and checks
  /// the elements of the chart that are near the offset,
  /// then makes a [BarTouchResponse] from the elements that has been touched.
  @override
  BarTouchResponse handleTouch(FlTouchInput touchInput, Size size) {
    final touchedSpot = _getNearestTouchedSpot(size, touchInput.getOffset(), _groupBarsPosition);
    return BarTouchResponse(touchedSpot, touchInput);
  }

  /// find the nearest spot base on the touched offset
  BarTouchedSpot _getNearestTouchedSpot(Size viewSize, Offset touchedPoint,
      List<_GroupBarsPosition> groupBarsPosition) {
    if (groupBarsPosition == null) {
      final groupsX = _calculateGroupsX(viewSize, data.barGroups, data.alignment);
      groupBarsPosition = _calculateGroupAndBarsPosition(viewSize, groupsX, data.barGroups);
    }

    final chartViewSize = getChartUsableDrawSize(viewSize);

    /// Find the nearest barRod
    for (var i = 0; i < groupBarsPosition.length; i++) {
      final groupBarPos = groupBarsPosition[i];
      for (var j = 0; j < groupBarPos.barsX.length; j++) {
        final barX = groupBarPos.barsX[j];
        final barWidth = targetData.barGroups[i].barRods[j].width;
        final halfBarWidth = barWidth / 2;

        double barTopY;
        double barBotY;

        final isPositive = targetData.barGroups[i].barRods[j].y > 0;
        if (isPositive) {
          barTopY = getPixelY(targetData.barGroups[i].barRods[j].y, chartViewSize);
          barBotY = getPixelY(0, chartViewSize);
        } else {
          barTopY = getPixelY(0, chartViewSize);
          barBotY = getPixelY(targetData.barGroups[i].barRods[j].y, chartViewSize);
        }

        final backDrawBarY =
        getPixelY(targetData.barGroups[i].barRods[j].backDrawRodData.y, chartViewSize);
        final touchExtraThreshold = targetData.barTouchData.touchExtraThreshold;

        final isXInTouchBounds =
            (touchedPoint.dx <= barX + halfBarWidth + touchExtraThreshold.right) &&
                (touchedPoint.dx >= barX - halfBarWidth - touchExtraThreshold.left);

        final isYInBarBounds = (touchedPoint.dy <= barBotY + touchExtraThreshold.bottom) &&
            (touchedPoint.dy >= barTopY - touchExtraThreshold.top);

        bool isYInBarBackDrawBounds;
        if (isPositive) {
          isYInBarBackDrawBounds = (touchedPoint.dy <= barBotY + touchExtraThreshold.bottom) &&
              (touchedPoint.dy >= backDrawBarY - touchExtraThreshold.top);
        } else {
          isYInBarBackDrawBounds = (touchedPoint.dy >= barTopY - touchExtraThreshold.top) &&
              (touchedPoint.dy <= backDrawBarY + touchExtraThreshold.bottom);
        }

        final isYInTouchBounds =
            (targetData.barTouchData.allowTouchBarBackDraw && isYInBarBackDrawBounds) ||
                isYInBarBounds;

        if (isXInTouchBounds && isYInTouchBounds) {
          final nearestGroup = targetData.barGroups[i];
          final nearestBarRod = nearestGroup.barRods[j];
          final nearestSpot = FlSpot(nearestGroup.x.toDouble(), nearestBarRod.y);
          final nearestSpotPos = Offset(barX, getPixelY(nearestSpot.y, chartViewSize));

          var touchedStackIndex = -1;
          BarChartRodStackItem touchedStack;
          for (var stackIndex = 0; stackIndex < nearestBarRod.rodStackItems.length; stackIndex++) {
            final stackItem = nearestBarRod.rodStackItems[stackIndex];
            final fromPixel = getPixelY(stackItem.fromY, chartViewSize);
            final toPixel = getPixelY(stackItem.toY, chartViewSize);
            if (touchedPoint.dy <= fromPixel && touchedPoint.dy >= toPixel) {
              touchedStackIndex = stackIndex;
              touchedStack = stackItem;
              break;
            }
          }

          return BarTouchedSpot(
              nearestGroup,
              i,
              nearestBarRod,
              j,
              touchedStack,
              touchedStackIndex,
              nearestSpot,
              nearestSpotPos);
        }
      }
    }

    return null;
  }


  /// Determines should it redraw the chart or not.
  ///
  /// If there is a change in the [BarChartData],
  /// [BarChartPainter] should repaint itself.
  @override
  bool shouldRepaint(BarChartPainter oldDelegate) => oldDelegate.data != data;
}

class _GroupBarsPosition {
  final double groupX;
  final List<double> barsX;

  _GroupBarsPosition(this.groupX, this.barsX);
}
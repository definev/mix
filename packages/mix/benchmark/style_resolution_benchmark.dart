import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mix/mix.dart';

import '../test/helpers/testing_utils.dart';

// Run from packages/mix:
// flutter test benchmark/style_resolution_benchmark.dart --reporter expanded
// Timings are diagnostic; they deliberately have no pass/fail threshold.
void main() {
  test('property and style resolution benchmarks', () {
    final context = MockBuildContext();
    final value = Prop.value(42);
    final mix = Prop.mix(EdgeInsetsMix.all(8));
    final style = BoxStyler().color(const Color(0xff123456)).size(100, 100);
    var checksum = 0;

    measure('single value resolve', 100000, () {
      checksum += value.resolveProp(context);
    });
    measure('single Mix resolve', 20000, () {
      checksum += mix.resolveProp(context).left.toInt();
    });
    measure('static Box style build', 10000, () {
      checksum += style.build(context).spec.constraints!.maxWidth.toInt();
    });

    for (final depth in [8, 32, 128, 512]) {
      final inputs = List.generate(depth, Prop.value);
      measure('merge $depth sources and resolve', 2000, () {
        var merged = inputs.first;
        for (final prop in inputs.skip(1)) {
          merged = merged.mergeProp(prop);
        }
        checksum += merged.resolveProp(context);
      });
    }

    expect(checksum, greaterThan(0));
  });

  testWidgets('widget state and token resolution benchmarks', (tester) async {
    const contextKey = Key('benchmark-context');
    const primary = ColorToken('primary');
    const spacing = SpaceToken('spacing');
    final tokenStyle = BoxStyler()
        .color(primary())
        .padding(EdgeInsetsMix.all(spacing()));
    final stateStyle = tokenStyle
        .onHovered(BoxStyler().color(const Color(0xffabcdef)))
        .onPressed(BoxStyler().width(120));

    await tester.pumpWidget(
      MixScope(
        tokens: {primary: const Color(0xff123456), spacing: 12.0},
        child: WidgetStateProvider(
          states: const {WidgetState.hovered, WidgetState.pressed},
          child: Builder(key: contextKey, builder: (_) => const SizedBox()),
        ),
      ),
    );
    final context = tester.element(find.byKey(contextKey));
    var checksum = 0;
    measure('token Box style build', 10000, () {
      checksum += tokenStyle.build(context).spec.padding!.horizontal.toInt();
    });
    measure('hover/pressed Box style build', 10000, () {
      checksum += stateStyle.build(context).spec.constraints!.maxWidth.toInt();
    });
    expect(checksum, greaterThan(0));
  });

  testWidgets('static style widget update benchmark', (tester) async {
    Widget build(int update) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: List.generate(100, (index) {
            return StyleAnimationBuilder<BoxSpec>(
              // Style resolution produces a fresh spec on each parent build.
              spec: StyleSpec(spec: BoxSpec(alignment: Alignment.center)),
              builder: (_, spec) => SizedBox(key: ValueKey('$index/$update')),
            );
          }),
        ),
      );
    }

    for (var update = 0; update < 20; update++) {
      await tester.pumpWidget(build(update));
    }
    final samples = <int>[];
    for (var sample = 0; sample < 7; sample++) {
      final stopwatch = Stopwatch()..start();
      for (var update = 0; update < 100; update++) {
        await tester.pumpWidget(build(update));
      }
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print('static widget update (100 widgets): ${samples[3] / 100} us/update');
  });
}

void measure(String label, int iterations, void Function() operation) {
  for (var warmup = 0; warmup < iterations; warmup++) {
    operation();
  }
  final samples = <int>[];
  for (var sample = 0; sample < 7; sample++) {
    final stopwatch = Stopwatch()..start();
    for (var iteration = 0; iteration < iterations; iteration++) {
      operation();
    }
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  // ignore: avoid_print
  print('$label: ${samples[3] / iterations} us/op');
}

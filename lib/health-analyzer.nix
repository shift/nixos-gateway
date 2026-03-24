{ lib, ... }:

let
  inherit (lib) filter foldl' length;
in
{
  # Calculate health score based on component weights and status
  # components: { name = { status = "0"|"1"; weight = int; }; }
  calculateScore =
    components:
    let
      # Filter only enabled/valid components
      validComponents = filter (c: c ? status && c ? weight) (builtins.attrValues components);

      # Calculate total possible weight and actual score
      totals =
        foldl'
          (acc: component: {
            totalWeight = acc.totalWeight + component.weight;
            actualScore = acc.actualScore + (if component.status == "1" then component.weight else 0);
          })
          {
            totalWeight = 0;
            actualScore = 0;
          }
          validComponents;
    in
    if totals.totalWeight > 0 then (totals.actualScore * 100) / totals.totalWeight else 0;

  # Analyze trend direction
  # history: [ score1, score2, ... ] (newest last)
  analyzeTrend =
    history:
    if length history < 2 then
      "stable"
    else
      let
        last = lib.last history;
        prev = lib.last (lib.init history);
      in
      if last > prev then
        "improving"
      else if last < prev then
        "degrading"
      else
        "stable";

  # Predict future score using linear regression (simplified)
  # history: [ score1, score2, ... ]
  predictScore =
    history:
    let
      n = length history;
    in
    if n < 2 then
      lib.last history # Not enough data
    else
      let
        # X coordinates (0, 1, 2...)
        xs = lib.range 0 (n - 1);
        # Y coordinates (scores)
        ys = history;

        # Means
        meanX = (lib.foldl' (a: b: a + b) 0 xs) / n;
        meanY = (lib.foldl' (a: b: a + b) 0 ys) / n;

        # Slope (m) calculation components
        numer = lib.foldl' (acc: i: acc + ((lib.elemAt xs i - meanX) * (lib.elemAt ys i - meanY))) 0 xs;
        denom = lib.foldl' (acc: i: acc + ((lib.elemAt xs i - meanX) * (lib.elemAt xs i - meanX))) 0 xs;

        slope = if denom != 0 then numer / denom else 0;
        intercept = meanY - (slope * meanX);
      in
      # Predict next value (x = n)
      (slope * n) + intercept;
}

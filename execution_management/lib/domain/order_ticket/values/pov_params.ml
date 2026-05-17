type t = { participation_rate : float }

let make ~participation_rate =
  if participation_rate <= 0.0 || participation_rate > 1.0 then
    invalid_arg "Pov_params.make: participation_rate must be in (0, 1]";
  { participation_rate }

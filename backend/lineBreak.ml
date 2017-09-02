
let print_for_debug msgln =
  print_endline msgln

open HorzBox

let ( ~. ) = float_of_int
let ( ~@ ) = int_of_float


let widinfo_zero =
  {
    natural= SkipLength.zero;
    shrinkable= SkipLength.zero;
    stretchable= SkipLength.zero;
    fils= 0;
  }

let ( +%@ ) wi1 wi2 =
  {
    natural= wi1.natural +% wi2.natural;
    shrinkable= wi1.shrinkable +% wi2.shrinkable;
    stretchable= wi1.stretchable +% wi2.stretchable;
    fils= wi1.fils + wi2.fils;
  }

type frame_kind =
  | StandaloneFrame
  | HeadFrame
  | MiddleFrame
  | TailFrame

type metrics = skip_info * skip_height * skip_depth

type lb_pure_box =
  | Atom        of metrics * evaled_horz_box_main
  | OuterFrame  of metrics * decoration * lb_pure_box list
  | FixedFrame  of skip_width * skip_height * skip_depth * decoration * lb_pure_box list

type lb_box =
  | LBPure           of lb_pure_box
  | LBDiscretionary  of pure_badness * DiscretionaryID.t * lb_pure_box option * lb_pure_box option * lb_pure_box option
  | LBFrameBreakable of paddings * skip_width * skip_width * decoration * decoration * decoration * decoration * lb_box list


let natural wid =
  {
    natural     = wid;
    shrinkable  = SkipLength.zero;
    stretchable = SkipLength.zero;
    fils        = 0;
  }


let get_metrics (lphb : lb_pure_box) : metrics =
  match lphb with
  | Atom(metr, _)                   -> metr
  | OuterFrame(metr, _, _)          -> metr
  | FixedFrame(wid, hgt, dpt, _, _) -> (natural wid, hgt, dpt)

let get_total_metrics (lphblst : lb_pure_box list) : metrics =
  lphblst @|> (widinfo_zero, SkipLength.zero, SkipLength.zero) @|> List.fold_left (fun (wiacc, hacc, dacc) lphb ->
    let (wi, h, d) = get_metrics lphb in
      (wiacc +%@ wi, max hacc h, min dacc d)
  )


let get_width_info (lphb : lb_pure_box) =
  let (widinfo, _, _) = get_metrics lphb in widinfo


let get_width_info_opt = function
  | None      -> widinfo_zero
  | Some(lhb) -> get_width_info lhb


let append_horz_padding (lhblst : lb_box list) (pads : paddings) =
  List.append
    (LBPure(Atom((natural pads.paddingL, SkipLength.zero, SkipLength.zero), EvHorzEmpty)) :: lhblst)
    (LBPure(Atom((natural pads.paddingR, SkipLength.zero, SkipLength.zero), EvHorzEmpty)) :: [])


let append_horz_padding_pure (lphblst : lb_pure_box list) (widinfo : skip_info) (pads : paddings) =
  let lphblstnew =
    List.append
      (Atom((natural pads.paddingL, SkipLength.zero, SkipLength.zero), EvHorzEmpty) :: lphblst)
      (Atom((natural pads.paddingR, SkipLength.zero, SkipLength.zero), EvHorzEmpty) :: [])
  in
  let widinfonew =
    {
      natural     = widinfo.natural +% pads.paddingL +% pads.paddingR;
      shrinkable  = widinfo.shrinkable;
      stretchable = widinfo.stretchable;
      fils        = widinfo.fils;
    }
  in
    (lphblstnew, widinfonew)


let rec convert_list_for_line_breaking (hblst : horz_box list) : lb_box list =
  let rec aux acc hblst =
    match hblst with
    | [] -> List.rev acc

    | HorzDiscretionary(pnlty, phbopt0, phbopt1, phbopt2) :: tail ->
        let lphbopt0 = convert_pure_box_for_line_breaking_opt phbopt0 in
        let lphbopt1 = convert_pure_box_for_line_breaking_opt phbopt1 in
        let lphbopt2 = convert_pure_box_for_line_breaking_opt phbopt2 in
        let dscrid = DiscretionaryID.fresh () in
          aux (LBDiscretionary(pnlty, dscrid, lphbopt0, lphbopt1, lphbopt2) :: acc) tail

    | HorzPure(phb) :: tail ->
        let lphb = convert_pure_box_for_line_breaking phb in
          aux (LBPure(lphb) :: acc) tail

    | HorzFrameBreakable(pads, wid1, wid2, decoS, decoH, decoM, decoT, hblst) :: tail ->
        let lhblst = convert_list_for_line_breaking hblst in
        let lhblstnew = append_horz_padding lhblst pads in
          aux (LBFrameBreakable(pads, wid1, wid2, decoS, decoH, decoM, decoT, lhblstnew) :: acc) tail

  in
    aux [] hblst


and convert_list_for_line_breaking_pure (hblst : horz_box list) : lb_pure_box list =
  let rec aux acc hblst =
    match hblst with
    | [] -> List.rev acc

    | HorzDiscretionary(pnlty, phbopt0, phbopt1, phbopt2) :: tail ->
        let lphbopt0 = convert_pure_box_for_line_breaking_opt phbopt0 in
        begin
          match lphbopt0 with
          | None        -> aux acc tail
          | Some(lphb0) -> aux (lphb0 :: acc) tail
        end

    | HorzPure(phb) :: tail ->
        let lphb = convert_pure_box_for_line_breaking phb in
          aux (lphb :: acc) tail

    | HorzFrameBreakable(pads, wid1, wid2, decoS, decoH, decoM, decoT, hblstsub) :: tail ->
        let lphblst = convert_list_for_line_breaking_pure hblstsub in
        let (widinfo_sub, hgt, dpt) = get_total_metrics lphblst in
        let (lphblstnew, widinfo_total) = append_horz_padding_pure lphblst widinfo_sub pads in
          aux (OuterFrame((widinfo_total, hgt +% pads.paddingT, dpt -% pads.paddingB), decoS, lphblst) :: acc) tail
  in
    aux [] hblst

  
and convert_pure_box_for_line_breaking (phb : pure_horz_box) : lb_pure_box =
  match phb with
  | PHFixedString(((fontabrv, size) as info), word) ->
      let (otxt, wid, hgt, dpt) = FontInfo.get_metrics_of_word fontabrv size word in
        Atom((natural wid, hgt, dpt), EvHorzString(info, otxt))

  | PHFixedEmpty(wid) ->
      Atom((natural wid, SkipLength.zero, SkipLength.zero), EvHorzEmpty)

  | PHOuterEmpty(wid, widshrink, widstretch) ->
      Atom(({ natural = wid; shrinkable = widshrink; stretchable = widstretch; fils = 0; }, SkipLength.zero, SkipLength.zero), EvHorzEmpty)

  | PHOuterFil ->
      Atom(({ natural = SkipLength.zero; shrinkable = SkipLength.zero; stretchable = SkipLength.zero; fils = 1; }, SkipLength.zero, SkipLength.zero), EvHorzEmpty)

  | PHOuterFrame(pads, deco, hblst) ->
      let lphblst = convert_list_for_line_breaking_pure hblst in
      let (widinfo_sub, hgt, dpt) = get_total_metrics lphblst in
      let (lphblstnew, widinfo_total) = append_horz_padding_pure lphblst widinfo_sub pads in
        OuterFrame((widinfo_total, hgt +% pads.paddingT, dpt -% pads.paddingB), deco, lphblstnew)

  | PHInnerFrame(pads, deco, hblst) ->
      let lphblst = convert_list_for_line_breaking_pure hblst in
      let (widinfo_sub, hgt, dpt) = get_total_metrics lphblst in
      let (lphblstnew, widinfo_total) = append_horz_padding_pure lphblst widinfo_sub pads in
        FixedFrame(widinfo_total.natural, hgt +% pads.paddingT, dpt -% pads.paddingB, deco, lphblstnew)

  | PHFixedFrame(pads, wid_req, deco, hblst) ->
      let lphblst = convert_list_for_line_breaking_pure hblst in
      let (widinfo_sub, hgt, dpt) = get_total_metrics lphblst in
      let (lphblstnew, _) = append_horz_padding_pure lphblst widinfo_sub pads in
        FixedFrame(wid_req, hgt +% pads.paddingT, dpt -% pads.paddingB, deco, lphblstnew)


and convert_pure_box_for_line_breaking_opt (phbopt : pure_horz_box option) =
  match phbopt with
  | None      -> None
  | Some(phb) -> Some(convert_pure_box_for_line_breaking phb)


module WidthMap
: sig
    type t
    val empty : t
    val add_width_all : skip_info -> t -> t
    val add : DiscretionaryID.t -> skip_info -> t -> t
    val iter : (DiscretionaryID.t -> skip_info -> bool ref -> unit) -> t -> unit
    val remove : DiscretionaryID.t -> t -> t
  end
= struct

    module DiscretionaryIDMap = Map.Make (DiscretionaryID)

    type t = (skip_info * bool ref) DiscretionaryIDMap.t

    let empty = DiscretionaryIDMap.empty

    let add dscrid widinfo wmap = wmap |> DiscretionaryIDMap.add dscrid (widinfo, ref false)

    let iter f = DiscretionaryIDMap.iter (fun dscrid (widinfo, bref) -> f dscrid widinfo bref)

    let add_width_all (widinfo : skip_info) (wmap : t) : t =
      wmap |> DiscretionaryIDMap.map (fun (distinfo, bref) -> (distinfo +%@ widinfo, bref))

    let remove = DiscretionaryIDMap.remove

  end


module LineBreakGraph = FlowGraph.Make
  (DiscretionaryID)
  (struct
    type t = pure_badness
    let show = string_of_int
    let add = ( + )
    let compare b1 b2 = b1 - b2
    let zero = 0
  end)


module RemovalSet = MutableSet.Make
  (DiscretionaryID)


let paragraph_width = SkipLength.of_pdf_point 450.0 (* temporary; should be variable *)

let calculate_ratios (widrequired : skip_width) (widinfo_total : skip_info) : bool * float * skip_width =
  let widnatural = widinfo_total.natural in
  let widstretch = widinfo_total.stretchable in
  let widshrink  = widinfo_total.shrinkable in
  let nfil       = widinfo_total.fils in
  let widdiff = widrequired -% widnatural in
  let is_short = (widnatural <% widrequired) in
  let (ratio, widperfil) =
    if is_short then
      if nfil > 0 then  (* -- when the line contains fils -- *)
        (0., widdiff *% (1. /. (~. nfil)))
      else if nfil = 0 then
        if SkipLength.is_nearly_zero widstretch then (+.infinity, SkipLength.zero) else
          (widdiff /% widstretch, SkipLength.zero)
      else
        assert false
    else
      if SkipLength.is_nearly_zero widshrink then (-.infinity, SkipLength.zero) else (widdiff /% widshrink, SkipLength.zero)
  in
    (is_short, ratio, widperfil)


let rec determine_widths (wid_req : skip_width) (lphblst : lb_pure_box list) : evaled_horz_box list * skip_height * skip_depth * badness =
  let (widinfo_total, hgt_total, dpt_total) = get_total_metrics lphblst in
  let (is_short, ratio, widperfil) = calculate_ratios wid_req widinfo_total in
  let rec main_conversion is_short ratio widperfil lphb =
    match lphb with
    | Atom((widinfo, _, _), evhb) ->
        let nfil = widinfo.fils in
          if nfil > 0 then
            (EvHorz(widinfo.natural +% widperfil, evhb), 0)
          else if nfil = 0 then
            let widdiff =
              if is_short then widinfo.stretchable *% ratio
                          else widinfo.shrinkable *% ratio
            in
              (EvHorz(widinfo.natural +% widdiff, evhb), abs (~@ (ratio *. 100.0)))
          else
            assert false  (* -- nfil cannot be negative -- *)

    | OuterFrame((_, hgt_frame, dpt_frame), deco, lphblstsub) ->
        let pairlst = lphblstsub |> List.map (main_conversion is_short ratio widperfil) in
        let evhblst = pairlst |> List.map (fun (evhb, _) -> evhb) in
        let totalpb = pairlst |> List.fold_left (fun acc (_, pb) -> pb + acc) 0 in
        let wid_total = evhblst @|> SkipLength.zero @|> List.fold_left (fun acc (EvHorz(w, _)) -> acc +% w) in
          (EvHorz(wid_total, EvHorzFrame(hgt_frame, dpt_frame, deco, evhblst)), totalpb)

    | FixedFrame(wid_frame, hgt_frame, dpt_frame, deco, lphblstsub) ->
        let (evhblst, _, _, pb) = determine_widths wid_frame lphblstsub in
          (EvHorz(wid_frame, EvHorzFrame(hgt_frame, dpt_frame, deco, evhblst)), 0)

  in
      let pairlst = lphblst |> List.map (main_conversion is_short ratio widperfil) in
      let evhblst = pairlst |> List.map (fun (evhb, _) -> evhb) in
      let totalpb = pairlst |> List.fold_left (fun acc (_, pb) -> pb + acc) 0 in
      let badns =
        if is_short then
          if totalpb >= 10000 then TooShort else Badness(totalpb)
        else
          if totalpb >= 10000 then TooLong(totalpb) else Badness(totalpb)
      in
      (* begin : for debug *)
      let checksum =
        evhblst |> List.map (function
          | EvHorz(wid, _) -> wid
        ) |> List.fold_left ( +% ) SkipLength.zero
      in
      let () = print_for_debug ("natural = " ^ (SkipLength.show widinfo_total.natural) ^ ", " ^
                                (if is_short then
                                  "stretchable = " ^ (SkipLength.show widinfo_total.stretchable)
                                 else
                                  "shrinkable = " ^ (SkipLength.show widinfo_total.shrinkable)) ^ ", " ^
                                "nfil = " ^ (string_of_int widinfo_total.fils) ^ ", " ^
                                "ratio = " ^ (string_of_float ratio) ^ ", " ^
                                "checksum = " ^ (SkipLength.show checksum)) in
      (* end : for debug *)
        (evhblst, hgt_total, dpt_total, badns)


(* -- distance from the top of the paragraph and its first baseline -- *)
let first_leading = SkipLength.of_pdf_point 10.  (* temporary; should be variable *)


let break_into_lines (leading_required : SkipLength.t) (path : DiscretionaryID.t list) (lhblst : lb_box list) : intermediate_vert_box list =

  let calculate_vertical_skip (dptprev : skip_depth) (hgt : skip_height) : SkipLength.t =
    let leadingsub = leading_required -% dptprev -% hgt in
      if leadingsub <% SkipLength.zero then SkipLength.zero else leadingsub
  in

  let append_framed_lines
        (lines_in_frame : (lb_pure_box list) list)
        (acclines_before : (lb_pure_box list) list)
        (accline_before : lb_pure_box list)
        (decoS : decoration)
        (decoH : decoration)
        (decoM : decoration)
        (decoT : decoration)
        : (lb_pure_box list) list * lb_pure_box list =
    let rec aux
          (first : (lb_pure_box list) option)
          (last : (lb_pure_box list) option)
          (acclines : (lb_pure_box list) list)
          (lines : (lb_pure_box list) list)
        =
      match lines with
      | [] ->
          begin
            match last with
            | Some(accline) -> (acclines, accline)
            | None          -> (acclines, [])
          end

      | line :: [] ->  (* -- last line -- *)
          let metr_total = get_total_metrics line in
          begin
            match first with
            | Some(accline) ->
                aux None (Some(OuterFrame(metr_total, decoS, line) :: accline)) acclines []
            | None ->
                aux None (Some(OuterFrame(metr_total, decoT, line) :: [])) acclines []
          end

      | line :: tail ->
          let metr_total = get_total_metrics line in
          begin
            match first with
            | Some(accline) ->
                aux None None ((List.rev (OuterFrame(metr_total, decoH, line) :: accline)) :: acclines) tail
            | None ->
                aux None None ((OuterFrame(metr_total, decoM, line) :: []) :: acclines) tail
          end
    in
      aux (Some(accline_before)) None acclines_before lines_in_frame
  in

  let rec cut (acclines : (lb_pure_box list) list) (accline : lb_pure_box list) (lhblst : lb_box list) : (lb_pure_box list) list =
    match lhblst with
    | LBDiscretionary(_, dscrid, lphbopt0, lphbopt1, lphbopt2) :: tail ->
        if List.mem dscrid path then
          let acclinesub   = match lphbopt1 with None -> accline | Some(lphb1) -> lphb1 :: accline in
          let acclinefresh = match lphbopt2 with None -> []      | Some(lphb2) -> lphb2 :: [] in
            cut ((List.rev acclinesub) :: acclines) acclinefresh tail
        else
          let acclinenew   = match lphbopt0 with None -> accline | Some(lhb0) -> lhb0 :: accline in
            cut acclines acclinenew tail

    | LBPure(lphb) :: tail ->
        cut acclines (lphb :: accline) tail

    | LBFrameBreakable(pads, wid1, wid2, decoS, decoH, decoM, decoT, lhblst) :: tail ->
        let acclines_in_frame = cut [] [] lhblst in
        let (acclinesnew, acclinenew) = append_framed_lines (List.rev acclines_in_frame) acclines accline decoS decoH decoM decoT in
          cut acclinesnew acclinenew tail

    | [] ->
        (List.rev accline) :: acclines
  in

  let rec arrange (dptprev : skip_depth) (accvlines : intermediate_vert_box list) (lines : (lb_pure_box list) list) =
    match lines with
    | line :: tail ->
          let (evhblst, hgt, dpt, _) = determine_widths paragraph_width line in
          let vskip = calculate_vertical_skip dptprev hgt in
            arrange dpt (ImVertLine(hgt, dpt, evhblst) :: ImVertFixedBreakable(vskip) :: accvlines) tail 

    | [] -> List.rev accvlines
  in

  let acclines = cut [] [] lhblst in
    arrange (leading_required -% first_leading) [] (List.rev acclines)


let main (leading_required : SkipLength.t) (hblst : horz_box list) : intermediate_vert_box list =

  let get_badness_for_line_breaking (widrequired : skip_width) (widinfo_total : skip_info) : badness =
    let criterion_short = 10. in
    let criterion_long = -.1. in
    let (is_short, ratio, _) = calculate_ratios widrequired widinfo_total in
    let pb = abs (~@ (ratio *. 10000. /. (if is_short then criterion_short else criterion_short))) in
      if      ratio > criterion_short then TooShort
      else if ratio < criterion_long  then TooLong(pb)
      else Badness(pb)
  in

  let grph = LineBreakGraph.create () in

  let htomit : RemovalSet.t = RemovalSet.create 32 in

  let found_candidate = ref false in

  let update_graph (wmap : WidthMap.t) (dscridto : DiscretionaryID.t) (widinfobreak : skip_info) (pnltybreak : pure_badness) () : bool * WidthMap.t =
    begin
      LineBreakGraph.add_vertex grph dscridto ;
      found_candidate := false ;
      RemovalSet.clear htomit ;
      wmap |> WidthMap.iter (fun dscridfrom widinfofrom is_already_too_long ->
        let badns = get_badness_for_line_breaking paragraph_width (widinfofrom +%@ widinfobreak) in
          match badns with
          | Badness(pb) ->
              begin
                found_candidate := true ;
                LineBreakGraph.add_edge grph dscridfrom dscridto (pb + pnltybreak) ;
              end

          | TooShort    -> ()

          | TooLong(pb) ->
              if !is_already_too_long then
                begin
                  RemovalSet.add htomit dscridfrom ;
                end
              else
                begin
                  is_already_too_long := true ;
                  found_candidate := true ;
                  LineBreakGraph.add_edge grph dscridfrom dscridto pb ;
                end
                  
      ) ;
      (!found_candidate, RemovalSet.fold (fun dscrid wm -> wm |> WidthMap.remove dscrid) htomit wmap)
    end
  in

  let rec aux (wmap : WidthMap.t) (lhblst : lb_box list) =
    match lhblst with
    | LBDiscretionary(pnlty, dscrid, lphbopt0, lphbopt1, lphbopt2) :: tail ->
        let widinfo0 = get_width_info_opt lphbopt0 in
        let widinfo1 = get_width_info_opt lphbopt1 in
        let widinfo2 = get_width_info_opt lphbopt2 in
        let (found, wmapsub) = update_graph wmap dscrid widinfo1 pnlty () in
        let wmapnew =
          if found then
            wmapsub |> WidthMap.add_width_all widinfo0 |> WidthMap.add dscrid widinfo2
          else
            wmapsub |> WidthMap.add_width_all widinfo0
        in
          aux wmapnew tail

    | LBPure(lphb) :: tail ->
        let widinfo = get_width_info lphb in
        let wmapnew = wmap |> WidthMap.add_width_all widinfo in
          aux wmapnew tail

    | LBFrameBreakable(pads, wid1, wid2, _, _, _, _, lhblstsub) :: tail ->
        let wmapsub = aux wmap lhblstsub in
          aux wmapsub tail

    | [] ->
        let dscrid = DiscretionaryID.final in
        let (_, wmapfinal) = update_graph wmap dscrid widinfo_zero 0 () in
          wmapfinal
  in
  let wmapinit = WidthMap.empty |> WidthMap.add DiscretionaryID.beginning widinfo_zero in
  begin
    DiscretionaryID.initialize () ;
    LineBreakGraph.add_vertex grph DiscretionaryID.beginning ;
    let lhblst = convert_list_for_line_breaking hblst in
    let _ (* wmapfinal *) = aux wmapinit lhblst in
    let pathopt = LineBreakGraph.shortest_path grph DiscretionaryID.beginning DiscretionaryID.final in
      match pathopt with
      | None       -> (* -- when no discretionary point is suitable for line breaking -- *)
          [ImVertLine(SkipLength.zero, SkipLength.zero, [])] (* temporary *)
      | Some(path) ->
          break_into_lines leading_required path lhblst
  end

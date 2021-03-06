## inspect blavaan object (wrapper around lavInspect with
## some additions)
blavTech <- function(blavobject, what, ...) {

    blavInspect(blavobject, what, ...)
}

## use lavInspect everywhere we can:
blavInspect <- function(blavobject, what, ...) {

    stopifnot(inherits(blavobject, "blavaan"))

    what <- tolower(what)
  
    dotdotdot <- list(...)
    dotNames <- names(dotdotdot)
    add.labels <- TRUE
    if(any(dotNames == "add.labels")) add.labels <- dotdotdot$add.labels

    jagtarget <- inherits(blavobject@external$mcmcout, "runjags")
  
    ## whats unique to blavaan
    blavwhats <- c("start", "starting.values", "inits", "psrf",
                   "ac.10", "neff", "mcmc", "draws", "samples",
                   "n.chains", "cp", "dp", "postmode", "postmean",
                   "postmedian", "hpd", "jagnames", "stannames",
                   "fscores", "lvs", "fsmeans", "lvmeans", "mcobj",
                   "rhat", "n_eff")

    ## blavwhats that don't require do.fit
    blavnofit <- c("start", "starting.values", "inits", "n.chains", "cp", "dp",
                   "jagnames", "stannames")
  
    ## whats that are not handled
    nowhats <- c("mi", "modindices", "modification.indices",
                 "wls.est", "wls.obs", "wls.v")

    if(what %in% blavwhats){
        if(!(what %in% blavnofit) & !blavobject@Options$do.fit){
            stop(paste0("blavaan ERROR: ", what, " does not exist when do.fit = FALSE"))
        }
        if(jagtarget){
            idx <- blavobject@ParTable$jagpnum
            idx <- idx[!is.na(idx)]
        } else {
            idx <- blavobject@ParTable$stansumnum
            if("pxnames" %in% names(blavobject@ParTable)){
              drows <- grepl("^def", blavobject@ParTable$pxnames)
            } else {
              drows <- grepl("def", blavobject@ParTable$mat)
            }
            idx <- idx[blavobject@ParTable$free > 0 | drows]
        }
        labs <- lav_partable_labels(blavobject@ParTable, type = "free")
        if(what %in% c("start", "starting.values", "inits")){
            blavobject@external$inits
        } else if(what %in% c("psrf", "ac.10", "neff", "rhat", "n_eff")){
            if(jagtarget){
                mcmcsumm <- blavobject@external$mcmcout$summaries
            } else {
                mcmcsumm <- rstan::summary(blavobject@external$mcmcout)$summary
            }
            if(what %in% c("psrf", "rhat")){
                if(jagtarget){
                    OUT <- mcmcsumm[idx,'psrf']
                } else {
                    OUT <- mcmcsumm[idx,'Rhat']
                }
            }else if(what == "ac.10"){
                if(jagtarget){
                    OUT <- mcmcsumm[idx,'AC.10']
                } else {
                    stop("blavaan ERROR: autocorrelation stat currently unavailable for Stan.")
                }
            } else {
                if(jagtarget){
                    OUT <- mcmcsumm[idx,'SSeff']
                } else {
                    OUT <- mcmcsumm[idx,'n_eff']
                }
            }
            if(add.labels) names(OUT) <- labs
            OUT
        } else if(what %in% c("mcmc", "draws", "samples", "hpd")){
            ## add defined parameters to labels
            pt <- blavobject@ParTable
            pt$free[pt$op == ":="] <- max(pt$free, na.rm = TRUE) + 1:sum(pt$op == ":=")
            labs <- lav_partable_labels(pt, type = "free")
            draws <- make_mcmc(blavobject@external$mcmcout)
            draws <- lapply(draws, function(x) mcmc(x[,idx]))
            draws <- mcmc.list(draws)
            if(what == "hpd"){
                pct <- .95
                if("level" %in% dotNames) pct <- dotdotdot$level
                draws <- mcmc(do.call("rbind", draws))
                draws <- HPDinterval(draws, pct)
                if(add.labels) rownames(draws) <- labs
            }
            draws
        } else if(what == "mcobj"){
            blavobject@external$mcmcout
        } else if(what %in% c("fscores","lvs","fsmeans","lvmeans")){
            if(jagtarget){
                etas <- any(blavobject@external$mcmcout$monitor == "eta")
            } else {
                etas <- any(grepl("^eta", rownames(blavobject@external$stansumm)))
            }
            if(!etas) stop("blavaan ERROR: factor scores not saved; set save.lvs=TRUE")

            ## how many lvs, excluding phantoms
            lvmn <- lavInspect(blavobject, "mean.lv")
            if(inherits(lvmn, "list")){
                nlv <- length(lvmn[[1]])
            } else {
                nlv <- length(lvmn)
            }

            nsamp <- sum(lavInspect(blavobject, "nobs"))

            draws <- make_mcmc(blavobject@external$mcmcout)
            drawcols <- grep("^eta", colnames(draws[[1]]))

            if(jagtarget){
                ## remove phantoms
                drawcols <- drawcols[1:(nlv * nsamp)]
            } else {
                nfound <- length(drawcols)/nsamp
                drawcols <- drawcols[as.numeric(matrix(1:length(drawcols),
                                                       nsamp, nfound,
                                                       byrow=TRUE)[,1:nlv])]
            }
            draws <- lapply(draws, function(x) mcmc(x[,drawcols]))

            draws <- mcmc.list(draws)

            if((what %in% c("lvmeans", "fsmeans")) | ("means" %in% dotdotdot)){
                br <- TRUE
                if(jagtarget){
                    summ <- blavobject@external$mcmcout$summaries
                    summname <- "Mean"
                    br <- FALSE
                } else {
                    summ <- blavobject@external$stansumm
                    summname <- "mean"
                }
                mnrows <- grep("^eta", rownames(summ))

                draws <- matrix(summ[mnrows,summname], nsamp,
                                length(mnrows)/nsamp, byrow=br)[,1:nlv,drop=FALSE]
                colnames(draws) <- names(lvmn)
            }
            draws
        } else if(what == "n.chains"){
            draws <- make_mcmc(blavobject@external$mcmcout)
            length(draws)
        } else if(what == "cp"){
            blavobject@Options$cp
        } else if(what == "dp"){
            blavobject@Options$dp
        } else if(what %in% c("postmode", "postmean", "postmedian")){
            if(jagtarget){
                mcmcsumm <- blavobject@external$mcmcout$summaries
            } else {
                mcmcsumm <- rstan::summary(blavobject@external$mcmcout)$summary
            }

            if(what == "postmean"){
                if(jagtarget){
                    OUT <- mcmcsumm[idx,'Mean']
                } else {
                    OUT <- mcmcsumm[idx,'mean']
                }
            }else if(what == "postmedian"){
                if(jagtarget){
                    OUT <- mcmcsumm[idx,'Median']
                } else {
                    OUT <- mcmcsumm[idx,'50%']
                }
            } else {
                if(jagtarget){
                    OUT <- mcmcsumm[idx,'Mode']
                } else {
                    stop("blavaan ERROR: Modes unavailable for Stan.")
                }
            }
            if(add.labels) names(OUT) <- labs
            OUT
        } else if(what == "jagnames"){
            if(!jagtarget) stop("blavaan ERROR: JAGS was not used for model estimation.")
            OUT <- blavobject@ParTable$pxnames[blavobject@ParTable$free > 0]
            OUT <- OUT[order(blavobject@ParTable$free[blavobject@ParTable$free > 0])]
            if(add.labels) names(OUT) <- labs
            OUT
        } else if(what == "stannames"){
            if(jagtarget) stop("blavaan ERROR: Stan was not used for model estimation.")
            mcmcsumm <- rstan::summary(blavobject@external$mcmcout)$summary
            OUT <- rownames(mcmcsumm)[idx]
            if(add.labels) names(OUT) <- labs
            OUT
        }
    } else if(what %in% nowhats){
        stop(paste("blavaan ERROR: argument", what,
                   "not available for Bayesian models."))
    } else {
        ## we can use lavInspect
        lavargs <- c(dotdotdot, list(object = blavobject, what = what))
        do.call("lavInspect", lavargs)
    }
}

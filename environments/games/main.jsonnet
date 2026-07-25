local mcRouter = import 'games/mc-router/mc-router.libsonnet';
local minecraftBackup = import 'games/minecraft-backup/minecraft-backup.libsonnet';
local minecraft = import 'games/minecraft/minecraft.libsonnet';
local squaremap = import 'games/squaremap/squaremap.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  minecraft: minecraft.new(),
  mcRouter: mcRouter.new(),
  minecraftBackup: minecraftBackup.new(),
  squaremap: squaremap.new(),
})

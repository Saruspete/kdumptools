#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>

static const char *probed_func = "devmem_is_allowed";

/* Return-probe handler: force return value to be 1. */
static int ret_handler(struct kretprobe_instance *ri, struct pt_regs *regs)
{
#if defined(__i386__) && !defined(__KERNEL__)
	regs->eax = 1;
#else
	regs->ax = 1;
#endif
	return 0;
}

static struct kretprobe my_kretprobe = {
	.handler = ret_handler,
	/* Probe up to 20 instances concurrently. */
	.maxactive = 20
};

static int __init kretprobe_init(void)
{
	int ret;
	my_kretprobe.kp.symbol_name = (char *)probed_func;

	if ((ret = register_kretprobe(&my_kretprobe)) < 0) {
		printk("allow_devmem: register_kretprobe failed, returned %d\n", ret);
		return -1;
	}
	printk("allow_devmem: Planted return probe at %p\n", my_kretprobe.kp.addr);

	return 0;
}

static void __exit kretprobe_exit(void)
{
	unregister_kretprobe(&my_kretprobe);
	printk("allow_devmem: kretprobe unregistered\n");
	/* nmissed > 0 suggests that maxactive was set too low. */
	printk("allow_devmem: Missed probing %d instances of %s\n",
		my_kretprobe.nmissed, probed_func);
}

module_init(kretprobe_init)
module_exit(kretprobe_exit)
MODULE_LICENSE("GPL");
